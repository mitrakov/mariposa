import java.net.*;
import java.util.*;
import java.util.concurrent.*;

@SuppressWarnings("CallToPrintStackTrace")
public class Synchronizer {
    private final List<String> allHosts;
    private final int port;
    private final String myHostName;

    public Synchronizer(List<String> allHosts, int port) {
        this.allHosts = allHosts;
        this.port = port;
        this.myHostName = resolveMyHostName();
    }

    public String resolveMyHostName() {
        try {
            for (final var iface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (iface.isLoopback() || !iface.isUp()) continue;    // skip 127.0.0.1 and disabled interfaces
                for (final var address : Collections.list(iface.getInetAddresses())) {
                    for (final var host : allHosts) try {
                        if (address.equals(InetAddress.getByName(host)))
                            return host;    
                    } catch (Exception ignored) {}
                }
            }
        } catch (Exception e) { e.printStackTrace();}
        return "UNKNOWN_HOST";
    }

    public void waitForAllNodes(String scriptName) {
        final var pendingHosts = new HashMap<String, Boolean>();     // map of all nodes except me
        for (String host : allHosts) {
            if (!host.equals(myHostName))
                pendingHosts.put(host, true);
        }

        if (pendingHosts.isEmpty()) return; // edge case for N=1

        System.out.printf("\n[SYNC] Success: '%s'. Waiting for %s\n", scriptName, pendingHosts.keySet());

        try (final var socket = new DatagramSocket(port)) {
            socket.setSoTimeout(1000); // timeout 1 sec. for "granularity"
            final var buffer = new byte[1024];
            final var bytes = (myHostName + ":" + scriptName).getBytes();

            // dedicated thread to make retries every 2 seconds
            final var scheduler = Executors.newSingleThreadScheduledExecutor();
            scheduler.scheduleAtFixedRate(() -> {
                if (!pendingHosts.isEmpty()) {
                    broadcastMessage(socket, allHosts, bytes);
                }
            }, 200, 2000, TimeUnit.MILLISECONDS);

            while (!pendingHosts.isEmpty()) {
                try {
                    final var packet = new DatagramPacket(buffer, buffer.length);
                    socket.receive(packet); // block for 500ms

                    final var msg = new String(packet.getData(), 0, packet.getLength()).split(":");
                    if (msg.length < 2) continue;

                    final var senderHost = msg[0];
                    final var senderScript = msg[1];

                    // processing
                    if (senderScript.equals(scriptName)) {
                        if (pendingHosts.remove(senderHost) != null) {
                            System.out.printf("\n[SYNC] Node %s completed '%s'. Remaining: %s\n",
                                    senderHost, scriptName, pendingHosts.keySet());
                        }
                    }
                } catch (SocketTimeoutException ignored) {  // ignore 1 se.c timeout exceptions
                } catch (Exception e) { e.printStackTrace(); }
            }

            scheduler.shutdown();

            broadcastMessage(socket, allHosts, bytes);
            System.out.printf("\n[SYNC] ALL NODES DONE: '%s'\n", scriptName);
        } catch (Exception e) { e.printStackTrace(); }
    }

    private void broadcastMessage(DatagramSocket socket, List<String> hosts, byte[] message) {
        for (final var host : hosts) {
            if (!host.equals(myHostName)) try {
                socket.send(new DatagramPacket(message, message.length, InetAddress.getByName(host), port));
            } catch (Exception ignored) {}
        }
    }
}
