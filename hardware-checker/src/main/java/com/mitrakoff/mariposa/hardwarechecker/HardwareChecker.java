package com.mitrakoff.mariposa.hardwarechecker;

import com.kosprov.jargon2.api.Jargon2;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

public class HardwareChecker {
    public static void main(String[] args) {
        // CPU single-core
        Colours.styles(Colours.CYAN).println("\nChecking CPU...");
        checkCpu(1);

        // CPU multi-core
        final int cpuN = Runtime.getRuntime().availableProcessors();
        Colours.styles(Colours.CYAN).println("\nChecking CPU over %d cores...", cpuN);
        checkCpu(cpuN);
    }

    private static void checkCpu(int parallelism) {
        final long N = 1000;
        Colours.styles().println("Hash algorithm: argon2id$v=19$m=65536,t=1,p=%d; N = %d", parallelism, N);

        final long start = System.currentTimeMillis();
        for (int i = 0; i < N; i++)
            calcHash(parallelism);
        final double elapsedTimeSec = (System.currentTimeMillis() - start) / 1000d;

        Colours.styles().println("Took %.2f sec", elapsedTimeSec);
        Colours.styles(Colours.GREEN).println("Result: %.2f hashes/s", N / elapsedTimeSec);
    }

    private static String calcHash(int parallelism) {
        return Jargon2.jargon2Hasher()
                .type(Jargon2.Type.ARGON2id)
                .memoryCost(65536)
                .timeCost(1)
                .parallelism(parallelism)
                .password(UUID.randomUUID().toString().getBytes(StandardCharsets.UTF_8))
                .encodedHash();
    }
}
