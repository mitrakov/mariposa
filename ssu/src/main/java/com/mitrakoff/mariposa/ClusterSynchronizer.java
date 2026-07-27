package com.mitrakoff.mariposa;

import java.io.IOException;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class ClusterSynchronizer {
    private final List<String> allHosts;
    private final int port;
    private final String myHostName;

    public ClusterSynchronizer(List<String> allHosts, int port) {
        this.allHosts = allHosts;
        this.port = port;
        this.myHostName = resolveMyHostName();
    }

    /**
     * Bloquea el flujo hasta que todos los demás nodos confirmen que terminaron el mismo script.
     */
    public void waitForAllNodes(String scriptName) {
        // 1. Identificar qué hosts externos debemos esperar (excluyendo el propio de forma segura)
        Set<String> pendingHosts = new HashSet<>(allHosts);
        pendingHosts.remove(myHostName);

        if (pendingHosts.isEmpty()) {
            System.out.println("[Sync] Single node cluster or isolated host. No need to wait.");
            return;
        }

        System.out.println("[Sync] Waiting for peers to finish " + scriptName + ". Pending: " + pendingHosts);

        try (DatagramSocket socket = new DatagramSocket(port)) {
            // Timeout corto de 1.5s para retransmitir periódicamente y evitar pérdidas en UDP
            socket.setSoTimeout(1500);

            byte[] buffer = new byte[1024];
            String signalMessage = myHostName + ":" + scriptName;
            byte[] signalBytes = signalMessage.getBytes(StandardCharsets.UTF_8);

            // 2. Bucle principal de sincronización distribuida
            while (!pendingHosts.isEmpty()) {
                // Envía proactivamente nuestro estado a los demás (Heartbeat)
                broadcastSignal(socket, signalBytes, allHosts);

                try {
                    DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                    socket.receive(packet); // Espera un paquete de la red

                    String receivedData = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.UTF_8);

                    if (receivedData.contains(":")) {
                        String[] parts = receivedData.split(":");
                        String senderHost = parts[0];
                        String senderScript = parts[1];

                        // Al tener configuraciones idénticas, la comparación de texto es directa y segura
                        if (senderScript.equals(scriptName) && pendingHosts.contains(senderHost)) {
                            pendingHosts.remove(senderHost);
                            System.out.println("[Sync] -> Node " + senderHost + " synchronized for " + scriptName + ". Remaining: " + pendingHosts);
                        }
                    }
                } catch (SocketTimeoutException e) {
                    // Salta el timeout de red, el bucle continúa y vuelve a enviar el broadcast
                }
            }

            // Broadcast final de cortesía para asegurar que el clúster se entere de que cruzamos la barrera
            broadcastSignal(socket, signalBytes, allHosts);
            System.out.println("[Sync] Clean synchronization achieved for " + scriptName + " across all nodes!");

        } catch (Exception e) {
            System.err.println("[Sync Error] Failed during UDP synchronization barrier for " + scriptName);
            e.printStackTrace();
        }
    }

    private void broadcastSignal(DatagramSocket socket, byte[] message, List<String> hosts) {
        for (String host : hosts) {
            if (host.equals(myHostName)) continue;
            try {
                InetAddress address = InetAddress.getByName(host);
                DatagramPacket packet = new DatagramPacket(message, message.length, address, port);
                socket.send(packet);
            } catch (IOException e) {
                // Ignorar fallos temporales de enrutamiento
            }
        }
    }

    /**
     * Resuelve de forma robusta cuál elemento del JSON corresponde a esta máquina local,
     * comparando directamente a nivel de direcciones de red (IP/DNS).
     */
    public String resolveMyHostName() {
        try {
            // 1. Obtener todas las interfaces de red físicas de la máquina (en Mac: en0, en1, etc.)
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();

            for (NetworkInterface networkInterface : Collections.list(interfaces)) {
                // Ignorar interfaces inactivas o de loopback (localhost)
                if (networkInterface.isLoopback() || !networkInterface.isUp()) {
                    continue;
                }

                // 2. Revisar todas las direcciones IP asignadas a esta tarjeta de red
                Enumeration<InetAddress> addresses = networkInterface.getInetAddresses();
                for (InetAddress localAddress : Collections.list(addresses)) {
                    // Enfocarnos solo en IPv4 para evitar ruidos de IPv6
                    if (!(localAddress instanceof Inet4Address)) {
                        continue;
                    }

                    // 3. Comparar contra la lista del JSON
                    for (String host : allHosts) {
                        try {
                            InetAddress configAddress = InetAddress.getByName(host);
                            if (localAddress.equals(configAddress)) {
                                System.out.println("[Sync] Self-identity discovered matching config via physical interface: " + host);
                                return host;
                            }
                        } catch (UnknownHostException e) {
                            // Ignorar si un host del JSON no resuelve
                        }
                    }
                }
            }
            System.out.println("[Sync] Warning: Could not explicitly map any physical network address to cluster list.");
        } catch (Exception e) {
            System.err.println("[Sync] Critical error scanning physical network interfaces.");
            e.printStackTrace();
        }

        return "UNKNOWN_SELF";
    }
}
