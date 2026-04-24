package org.github.netudima.perf.tests.ascii;

public class SimpleAsciiChecker implements AsciiChecker {

    @Override
    public boolean isAscii(byte[] bytes) {
        for (byte b : bytes) {
            if (b < 0) return false;
        }
        return true;
    }
}
