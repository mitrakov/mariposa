import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;

/**
 * Simple utility to synchronize multinode cluster startup and shutdown scripts. Made specially for Hadoop clusters.
 * <pre>{@code
 * javac Ssu.java ClusterSynchronizer.java VanillaJsonParser.java
 * echo "Main-Class: Ssu" > ssu.mf    # make sure to add blank line at the end
 * jar cvmf mariposa-ssu.jar ssu.mf *.class
 * }</pre>
 */
@SuppressWarnings({"CallToPrintStackTrace", "unchecked"})
public class Ssu {
    private static DatagramSocket daemonListenSocket;

    public static void main(String[] args) {
        if (args.length == 0) printHelpAndQuit();

        try {
            // read config
            final var config = (Map<String, Object>) VanillaJsonParser.parse(Files.readString(Paths.get(args[0])));
            final var port = ((Number) config.get("port")).intValue();
            final var hosts = (List<String>) config.get("hosts");
            final var workDir = (String) config.get("workDir");
            final var startup = (List<String>) config.get("startup");
            final var shutdown = (List<String>) config.get("shutdown");
            System.out.printf("Port: %d\n", port);
            System.out.printf("Hosts: %s\n", hosts);
            System.out.printf("WorkDir: %s\n", workDir);
            System.out.printf("Startup scripts:  %s\n", startup);
            System.out.printf("Shutdown scripts: %s\n", shutdown);

            // create ClusterSynchronizer
            final var synchronizer = new ClusterSynchronizer(hosts, port);
            final var myHost = synchronizer.resolveMyHostName();
            System.out.printf("My host: %s:%d\n", myHost, port);

            // run startup scripts
            runScripts(startup, workDir, synchronizer, "STARTUP");

            // add shutdown hook
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                if (daemonListenSocket != null && !daemonListenSocket.isClosed())
                    daemonListenSocket.close(); // Release PORT to avoid "java.net.BindException: Address already in use"

                System.out.println("\n=== SIGTERM DETECTED! RUNNING GRACEFUL SHUTDOWN ===");
                broadcastShutdown(hosts, myHost, port);
                runScripts(shutdown, workDir, synchronizer, "SHUTDOWN");
                Runtime.getRuntime().halt(0);    // never use System.exit() in shutdown hooks!
            }));

            // listen for shutdown message from other nodes
            System.out.println("\n=== SSU RUNNING... Press CTRL+C or use 'kill <PID>' to run distributed graceful shutdown ===");
            listenForRemoteShutdown(myHost, port);
        } catch (Exception e) { e.printStackTrace(); }
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
                        System.out.printf("=== RECEIVED SHUTDOWN HOOK FROM: %s ===\n", nodeName);
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

    private static void runScripts(List<String> scripts, String workDir, ClusterSynchronizer synchronizer, String msg) {
        System.out.printf("\n=== %s START ===\n", msg);
        final var workDirectory = new File(workDir);
        for (final var script : scripts) {
            runScript(script, workDirectory);
            synchronizer.waitForAllNodes(script);
        }
        System.out.printf("\n=== %s FINISH ===\n", msg);
    }

    private static void runScript(String script, File workDir) {
        try {
            System.out.printf("\n=== EXECUTING: %s ===\n", script);
            final var pb = isWindows()
                    ? new ProcessBuilder("cmd.exe", "/c", script)
                    : new ProcessBuilder("./" + script);
            pb.directory(workDir);
            pb.redirectErrorStream(true);
            
            final var process = pb.start();
            try (final var reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null)
                    System.out.println(line);
            }
            process.waitFor();
        } catch (Exception e) { e.printStackTrace(); }
    }
    
    private static void printHelpAndQuit() {
        System.err.println("""
        Mariposa Simple Synchronization Utility.
        
        Usage:   java -jar mariposa-ssu.jar PORT JSON_CONF_FILE
        Example: java -jar mariposa-ssu.jar 9696 autorun.json
        
        Config example:
        {
          "port": 1030,
          "hosts": ["node1.host", "node2.host", "node3.host"],
          "workDir": "/home/hadoop/autorun",
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
