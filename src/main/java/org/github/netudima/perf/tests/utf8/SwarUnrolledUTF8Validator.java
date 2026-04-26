package org.github.netudima.perf.tests.utf8;

import org.openjdk.jmh.annotations.CompilerControl;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarUnrolledUTF8Validator extends BaseUTF8Validator {

    private static final long ASCII_MASK = 0x8080808080808080L;

    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean validate(byte[] bytes) {
        if (bytes == null)
            return false;
        int i = 0;
        // Process 4 longs (32 bytes) per iteration: OR them together for a single branch.
        // If any non-ASCII byte is present, find the first offending chunk and hand off.
        for (; i + 31 < bytes.length; i += 32) {
            long v0 = (long) VH_LE_LONG.get(bytes, i);
            long v1 = (long) VH_LE_LONG.get(bytes, i + 8);
            long v2 = (long) VH_LE_LONG.get(bytes, i + 16);
            long v3 = (long) VH_LE_LONG.get(bytes, i + 24);
            if (((v0 | v1 | v2 | v3) & ASCII_MASK) != 0) {
                if ((v0 & ASCII_MASK) != 0) return validateSlowPath(bytes, i);
                if ((v1 & ASCII_MASK) != 0) return validateSlowPath(bytes, i + 8);
                if ((v2 & ASCII_MASK) != 0) return validateSlowPath(bytes, i + 16);
                return validateSlowPath(bytes, i + 24);
            }
        }
        // 8-byte tail
        for (; i + 7 < bytes.length; i += 8) {
            if (((long) VH_LE_LONG.get(bytes, i) & ASCII_MASK) != 0)
                return validateSlowPath(bytes, i);
        }
        // byte tail
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return validateSlowPath(bytes, i);
        }
        return true;
    }
}
