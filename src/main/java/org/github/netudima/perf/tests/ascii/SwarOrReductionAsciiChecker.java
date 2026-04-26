package org.github.netudima.perf.tests.ascii;

import org.openjdk.jmh.annotations.CompilerControl;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarOrReductionAsciiChecker implements AsciiChecker {

    private static final long ASCII_MASK = 0x8080808080808080L;

    // byte order doesn't matter here
    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        int i = 0;
        long acc = 0;
        // accumulate without early exit
        for (; i + 7 < bytes.length; i += 8) {
            acc |= (long) VH_LE_LONG.get(bytes, i);
        }
        if ((acc & ASCII_MASK) != 0)
            return false;
        // byte tail
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return false;
        }
        return true;
    }
}
