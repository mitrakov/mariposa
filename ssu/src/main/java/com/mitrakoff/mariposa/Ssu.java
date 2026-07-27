package com.mitrakoff.mariposa;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.List;

@SuppressWarnings("CallToPrintStackTrace")
public class Ssu {
    private static DatagramSocket daemonListenSocket;

    public static void main(String[] args) {
        if (args.length != 2) printHelpAndQuit();

        try {
            // read config
            final var port = Integer.parseInt(args[0]);
            final var config = new ObjectMapper().readValue(Files.readString(Paths.get(args[1])), TheConfig.class);
            System.out.printf("Hosts: %s\n", config.hosts());
            System.out.printf("WorkDir: %s\n", config.workDir());
            System.out.printf("Startup scripts:  %s\n", config.startup());
            System.out.printf("Shutdown scripts: %s\n", config.shutdown());

            // create ClusterSynchronizer
            final var synchronizer = new ClusterSynchronizer(config.hosts(), port);
            final var myHost = synchronizer.resolveMyHostName();
            System.out.printf("My host: %s:%d\n", myHost, port);

            // run startup scripts
            runScripts(config.startup(), config.workDir(), synchronizer, "STARTUP");

            // add shutdown hook
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                if (daemonListenSocket != null && !daemonListenSocket.isClosed())
                    daemonListenSocket.close(); // Release PORT to avoid "java.net.BindException: Address already in use"

                System.out.println("\n=== SIGTERM DETECTED! RUNNING GRACEFUL SHUTDOWN ===");
                broadcastShutdown(config.hosts(), myHost, port);
                runScripts(config.shutdown(), config.workDir(), synchronizer, "SHUTDOWN");
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
            final var pb = new ProcessBuilder("./" + script);    // TODO: check Windows
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
}

record TheConfig(List<String> hosts, String workDir, List<String> startup, List<String> shutdown) {}
