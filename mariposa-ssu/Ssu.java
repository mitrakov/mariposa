import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

/**
 * Simple utility to synchronize multinode cluster startup and shutdown scripts. Made specially for Hadoop clusters.
 * JSON may contain ${ENV} variables. Hosts list may contain comma-separated hosts, e.g. "host1,host2,host3".
 * <pre>{@code
 * javac Ssu.java Synchronizer.java VanillaJsonParser.java && echo "Main-Class: Ssu" > ssu.mf && jar cvfm ssu.jar ssu.mf *.class
 * }</pre>
 */
@SuppressWarnings({"CallToPrintStackTrace", "unchecked"})
public class Ssu {
    private static DatagramSocket daemonListenSocket;

    public static void main(String[] args) {
        if (args.length == 0) printHelpAndQuit();

        try {
            // read file
            final var input = Files.readString(Paths.get(args[0]));

            // replace ${ENV}
            final var json = Pattern.compile("\\$\\{(\\w+)}").matcher(input).replaceAll(match -> {
                final var env = System.getenv(match.group(1));
                return Matcher.quoteReplacement(env != null ? env : match.group(0));
            });

            // parse json
            final var config = (Map<String, Object>) VanillaJsonParser.parse(json);
            final var port = ((Number) config.get("port")).intValue();
            final var workDir = (String) config.get("workDir");
            final var envFile = (String) config.get("environment");
            final var startup = (List<String>) config.get("startup");
            final var shutdown = (List<String>) config.get("shutdown");
            final var rawHosts = (List<String>) config.get("hosts");
            final var hosts = rawHosts.stream().flatMap(host -> Arrays.stream(host.split(","))).map(String::trim)
                    .filter(host -> !host.isEmpty()).toList(); // flatten comma-separated hosts, e.g. "host1,host2,host3"
            
            // load user ENV file
            final var env = loadEnvFile(envFile, workDir);

            // greetings
            System.out.printf("Port: %d\n", port);
            System.out.printf("Hosts: %s (total: %d)\n", hosts, hosts.size());
            System.out.printf("WorkDir: %s\n", workDir);
            System.out.printf("EnvFile: %s\n", envFile);
            System.out.printf("Startup scripts:  %s\n", startup);
            System.out.printf("Shutdown scripts: %s\n", shutdown);
            System.out.printf("Loaded ENV keys: %s\n", env.keySet());

            // create Synchronizer
            final var synchronizer = new Synchronizer(hosts, port);
            final var myHost = synchronizer.resolveMyHostName();
            System.out.printf("My host: %s\n", myHost);

            // run startup scripts
            runScripts(startup, workDir, env, synchronizer);

            // add shutdown hook
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                if (daemonListenSocket != null && !daemonListenSocket.isClosed())
                    daemonListenSocket.close(); // Release PORT to avoid "java.net.BindException: Address already in use"

                System.out.println("\n[SYNC] SIGTERM DETECTED! Running graceful shutdown");
                broadcastShutdown(hosts, myHost, port);
                runScripts(shutdown, workDir, env, synchronizer);
                Runtime.getRuntime().halt(0);    // never use System.exit() in shutdown hooks!
            }));

            // listen for shutdown message from other nodes
            System.out.println("\n[SYNC] Init done... Press CTRL+C or use 'kill <PID>' to run distributed graceful shutdown");
            listenForRemoteShutdown(myHost, port);
        } catch (Exception e) { e.printStackTrace(); }
    }

    private static Map<String, String> loadEnvFile(String envFileName, String workDir) {
        if (envFileName == null) return Collections.emptyMap();
        
        final var result = new TreeMap<String, String>();
        final var path = workDir != null ? Paths.get(workDir, envFileName) : Paths.get(envFileName);
        try (var br = new BufferedReader(new FileReader(path.toFile()))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.replaceAll("^export\\s+", "").trim(); // remove "export" keyword, if any
                if (line.isEmpty() || line.startsWith("#")) continue;
                
                final var parts = line.split("=", 2);
                result.put(parts[0].trim(), parts[1].trim());
            }
        } catch (Exception e) { e.printStackTrace(); }
        return result;
    }

    private static void listenForRemoteShutdown(String myHost, int port) {
        try {
            daemonListenSocket = new DatagramSocket(null);
            daemonListenSocket.setReuseAddress(true);
            daemonListenSocket.bind(new InetSocketAddress(port));

            final var buffer = new byte[1024];
            while (!daemonListenSocket.isClosed()) {
                final var packet = new DatagramPacket(buffer, buffer.length);
                try {
                    daemonListenSocket.receive(packet);
                } catch (Exception ignored) {}

                final var msg = new String(packet.getData(), 0, packet.getLength());
                if (msg.endsWith(":SHUTDOWN_TRIGGERED")) {
                    final var nodeName = msg.split(":")[0];
                    if (!nodeName.equals(myHost)) {
                        System.out.printf("[SYNC] RECEIVED SHUTDOWN HOOK FROM: %s\n", nodeName);
                        System.exit(0);    // call own shutdown hook
                    }
                }
            }
        } catch (Exception e) { e.printStackTrace(); }
    }

    private static void broadcastShutdown(List<String> hosts, String myHost, int port) {
        try (DatagramSocket socket = new DatagramSocket()) {
            final var data = (myHost + ":SHUTDOWN_TRIGGERED").getBytes();
            for (final var host : hosts) {
                if (!host.equals(myHost))
                    socket.send(new DatagramPacket(data, data.length, InetAddress.getByName(host), port));
            }
        } catch (Exception e) { e.printStackTrace(); }
    }

    private static void runScripts(List<String> scripts, String workDir, Map<String, String> env, Synchronizer synchronizer) {
        final var workDirectory = new File(workDir);
        for (final var script : scripts) {
            runScript(script, workDirectory, env);
            synchronizer.waitForAllNodes(script);
        }
    }

    private static void runScript(String script, File workDir, Map<String, String> env) {
        try {
            System.out.printf("\n[SYNC] RUN: '%s'\n", script);
            final var pb = isWindows()
                    ? new ProcessBuilder("cmd.exe", "/c", script)
                    : new ProcessBuilder("./" + script);
            pb.directory(workDir);
            pb.environment().putAll(env);
            pb.inheritIO();     // use the same stdin, stdout and stderr

            final var status = pb.start().waitFor();
            if (status != 0)
                System.exit(status);
        } catch (Exception e) { e.printStackTrace(); System.exit(1); }
    }

    private static void printHelpAndQuit() {
        System.err.println("""
        Mariposa Simple Synchronization Utility.
        
        Usage:   java -jar mariposa-ssu.jar JSON_CONF_FILE
        Example: java -jar mariposa-ssu.jar autorun.json
        
        Config example:
        {
          "port": 1030,
          "hosts": ["node1.host", "192.168.1.11", "${ENV_COMMA_SEP_HOSTS}"],
          "workDir": "/home/hadoop/autorun",
          "environment": "vars.env",
          "startup": [
            "script1.sh",
            "script2.sh",
            "script3.sh"
          ],
          "shutdown": [
            "graceful-shutdown.sh"
          ]
        }
        """);
        System.exit(1);
    }

    private static boolean isWindows() {
        return System.getProperty("os.name").toLowerCase().contains("win");
    }
}
