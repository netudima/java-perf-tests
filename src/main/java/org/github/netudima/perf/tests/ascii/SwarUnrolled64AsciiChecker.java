package org.github.netudima.perf.tests.ascii;

import org.openjdk.jmh.annotations.CompilerControl;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarUnrolled64AsciiChecker implements AsciiChecker {

    private static final long ASCII_MASK = 0x8080808080808080L;

    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        int i = 0;
        // 8 longs (64 bytes) per iteration — one stride per cache line
        for (; i + 63 < bytes.length; i += 64) {
            long v = (long) VH_LE_LONG.get(bytes, i)
                   | (long) VH_LE_LONG.get(bytes, i +  8)
                   | (long) VH_LE_LONG.get(bytes, i + 16)
                   | (long) VH_LE_LONG.get(bytes, i + 24)
                   | (long) VH_LE_LONG.get(bytes, i + 32)
                   | (long) VH_LE_LONG.get(bytes, i + 40)
                   | (long) VH_LE_LONG.get(bytes, i + 48)
                   | (long) VH_LE_LONG.get(bytes, i + 56);
            if ((v & ASCII_MASK) != 0)
                return false;
        }
        // 32-byte tail
        for (; i + 31 < bytes.length; i += 32) {
            long v = (long) VH_LE_LONG.get(bytes, i)
                   | (long) VH_LE_LONG.get(bytes, i +  8)
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
