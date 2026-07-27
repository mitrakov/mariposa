package com.mitrakoff.mariposa;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

record TheConfig(
    String workDir,
    List<String> hosts, 
    List<String> startup, 
    List<String> shutdown
) {}

public class Ssu {
    private static final int CLUSTER_PORT = 9696;
    private static DatagramSocket daemonListenSocket;
    private static ClusterSynchronizer synchronizer;
    private static TheConfig config;
    private static String myIdentity;

    public static void main(String[] args) {
        if (args.length == 0) {
            System.err.println("Error: Please provide the path to the JSON file.");
            System.exit(1);
        }

        try {
            Path filePath = Paths.get(args[0]);
            String jsonInput = Files.readString(filePath);

            ObjectMapper mapper = new ObjectMapper();
            config = mapper.readValue(jsonInput, TheConfig.class);

            synchronizer = new ClusterSynchronizer(config.hosts(), CLUSTER_PORT);
            myIdentity = synchronizer.resolveMyHostName();

            System.out.println("--- Starting Synchronized Cluster Daemon ---");
            System.out.println("Hosts: " + config.hosts());
            System.out.println("My Identity: " + myIdentity);

            // 1. BUCLE DE INICIO (STARTUP) - Si falla aquí, muere sin Hook de apagado
            System.out.println("\n[Executing Startup Stage]");
            for (String script : config.startup()) {
                runLocalScript(script, config.workDir());
                synchronizer.waitForAllNodes(script);
            }

            // 2. EL CLÚSTER ESTÁ LISTO -> AHORA SÍ REGISTRAMOS EL HOOK
            System.out.println("\n[Status] All startup scripts completed. Cluster Services are ONLINE.");

            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                System.out.println("\n[Local Signal] SIGTERM/Ctrl+C detected! Notifying cluster...");
                
                if (daemonListenSocket != null && !daemonListenSocket.isClosed()) {
                    daemonListenSocket.close();
                }

                // Enviar la señal de pánico a los demás nodos
                broadcastClusterMessage(myIdentity + ":SHUTDOWN_TRIGGERED", config.hosts(), CLUSTER_PORT);

                // Ejecutar la fase de apagado sincronizada en reversa
                executeClusterShutdownStage();

                System.out.println("[Process] Graceful cluster-wide shutdown complete. Forcing clean exit 0.");
                Runtime.getRuntime().halt(0);
            }));

            // 3. BUCLE PRINCIPAL (Aprovechamos el puerto UDP aquí mismo en lugar de un hilo extra)
            System.out.println("[Status] Daemon is idling. Listening for remote shutdown or local Ctrl+C...");
            listenForRemoteShutdown(CLUSTER_PORT);

        } catch (Exception e) {
            System.err.println("Critical failure in orchestration engine.");
            e.printStackTrace();
        }
    }

    /**
     * Bucle principal de espera activa. Reutiliza el puerto UDP para capturar
     * si otra máquina inició el proceso de apagado.
     */
    private static void listenForRemoteShutdown(int port) {
        try {
            // Inicializar la variable estática global
            daemonListenSocket = new DatagramSocket(null);
            daemonListenSocket.setReuseAddress(true);
            daemonListenSocket.bind(new InetSocketAddress(port));

            byte[] buffer = new byte[1024];

            // El bucle continuará de por vida hasta que salte una excepción de cierre
            while (!daemonListenSocket.isClosed()) {
                DatagramPacket packet = new DatagramPacket(buffer, buffer.length);

                // Si el hook invoca a daemonListenSocket.close() mientras el hilo está bloqueado aquí,
                // esta llamada arrojará un SocketException controlado de inmediato, liberando el hilo.
                daemonListenSocket.receive(packet);

                String msg = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.UTF_8);
                if (msg.contains(":SHUTDOWN_TRIGGERED")) {
                    String senderNode = msg.split(":")[0];

                    if (!senderNode.equals(myIdentity)) {
                        System.out.println("\n[Network Alert] Received remote shutdown command from node: " + senderNode);
                        System.exit(0);
                    }
                }
            }
        } catch (java.net.SocketException e) {
            // Esta excepción saltará intencionalmente cuando el Hook cierre el socket. 
            // Es un comportamiento limpio y completamente esperado para terminar el hilo de espera.
            System.out.println("[Network] Standby listener socket released cleanly by shutdown hook.");
        } catch (Exception e) {
            System.err.println("Error in main execution loop.");
            e.printStackTrace();
        }
    }


    /**
     * Corre la lista de apagado sincronizando paso a paso.
     */
    private static void executeClusterShutdownStage() {
        System.out.println("\n[Executing Synchronized Shutdown Stage]");
        List<String> shutdownScripts = config.shutdown();

        if (shutdownScripts == null || shutdownScripts.isEmpty()) {
            return;
        }

        for (String script : shutdownScripts) {
            System.out.println("[Shutdown] Starting step: ./" + script);
            runLocalScript(script, config.workDir());
            // Sincronización distribuida: nadie avanza al siguiente servicio hasta que todos apaguen el actual
            synchronizer.waitForAllNodes(script);
        }
    }

    private static void broadcastClusterMessage(String message, List<String> hosts, int port) {
        byte[] data = message.getBytes(StandardCharsets.UTF_8);
        try (DatagramSocket socket = new DatagramSocket()) {
            for (String host : hosts) {
                if (host.equals(myIdentity)) continue;
                try {
                    socket.send(new DatagramPacket(data, data.length, java.net.InetAddress.getByName(host), port));
                } catch (Exception e) {
                    // Ignorar nodos caídos
                }
            }
        } catch (Exception e) {
            System.err.println("Failed to broadcast shutdown trigger.");
        }
    }

    private static void runLocalScript(String script, String workDir) {
        try {
            ProcessBuilder pb = new ProcessBuilder("./" + script);
            pb.directory(new File(workDir));
            pb.redirectErrorStream(true);
            Process process = pb.start();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    System.out.println("  [OUTPUT] " + line);
                }
            }
            process.waitFor();
        } catch (Exception e) {
            System.err.println("Failed local script execution: " + script);
        }
    }
}
