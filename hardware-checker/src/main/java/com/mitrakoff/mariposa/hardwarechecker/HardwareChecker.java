package com.mitrakoff.mariposa.hardwarechecker;

import de.mkammerer.argon2.*;
import java.util.UUID;

public class HardwareChecker {
    private static final Argon2 argon2 = Argon2Factory.create();

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
        Colours.styles().println("N = %d; hash example: %s", N, calcHash(parallelism));

        final long start = System.currentTimeMillis();
        for (int i = 0; i < N; i++)
            calcHash(parallelism);
        final double elapsedTimeSec = (System.currentTimeMillis() - start) / 1000d;

        Colours.styles().println("Took %.2f sec", elapsedTimeSec);
        Colours.styles(Colours.GREEN).println("Result: %.2f hashes/s", N / elapsedTimeSec);
    }

    private static String calcHash(int parallelism) {
        return argon2.hash(1, 65536, parallelism, UUID.randomUUID().toString().toCharArray());
    }
}
