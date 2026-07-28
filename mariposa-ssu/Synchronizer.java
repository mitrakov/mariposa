import java.net.*;
import java.util.*;

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
        final var pendingHosts = new HashSet<>(allHosts);
        pendingHosts.remove(myHostName);    // remove myself from the set
        if (pendingHosts.isEmpty()) return; // edge case for N=1

        System.out.printf("\n[SYNC] Success: '%s'. Waiting for %s\n", scriptName, pendingHosts);
        try (final var socket = new DatagramSocket(port)) {
            final var buffer = new byte[1024];
            final var bytes = (myHostName + ":" + scriptName).getBytes();

            while (!pendingHosts.isEmpty()) try {
                broadcastMessage(socket, allHosts, bytes);

                final var packet = new DatagramPacket(buffer, buffer.length);
                socket.receive(packet);
                final var data = new String(packet.getData(), 0, packet.getLength()).split(":");
                final var senderHost = data[0];
                final var senderScript = data[1];

                if (senderScript.equals(scriptName) && pendingHosts.contains(senderHost)) {
                    pendingHosts.remove(senderHost);
                    System.out.printf("\n[SYNC] Node %s completed '%s'. Remaining: %s\n", senderHost, scriptName, pendingHosts);
                }
            } catch (Exception e) { e.printStackTrace(); }
            
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
