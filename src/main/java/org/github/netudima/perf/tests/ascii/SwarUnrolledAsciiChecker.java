package org.github.netudima.perf.tests.ascii;

import org.openjdk.jmh.annotations.CompilerControl;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarUnrolledAsciiChecker implements AsciiChecker {

    private static final long ASCII_MASK = 0x8080808080808080L;

    // byte order doesn't matter here
    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        int i = 0;
        // process 4 longs (32 bytes) per iteration — OR them together so the
        // CPU could pipeline all four loads and fold into a single branch
        for (; i + 31 < bytes.length; i += 32) {
            long v = (long) VH_LE_LONG.get(bytes, i)
                   | (long) VH_LE_LONG.get(bytes, i + 8)
                   | (long) VH_LE_LONG.get(bytes, i + 16)
                   | (long) VH_LE_LONG.get(bytes, i + 24);
            if ((v & ASCII_MASK) != 0)
                return false;
        }
        // 8-byte tail
        for (; i + 7 < bytes.length; i += 8) {
            if (((long) VH_LE_LONG.get(bytes, i) & ASCII_MASK) != 0)
                return false;
        }
        // byte tail
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return false;
        }
        return true;
    }
}
