package org.github.netudima.perf.tests.ascii;

import org.openjdk.jmh.annotations.CompilerControl;

public class SimpleForeachAsciiChecker implements AsciiChecker {

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        for (byte b : bytes) {
            if (b < 0)
                return false;
        }
        return true;
    }
}
