package org.github.netudima.perf.tests.utf8;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarUTF8Validator extends BaseUTF8Validator {

    private static final long ASCII_MASK = 0x8080808080808080L;

    // byte order doesn't matter here
    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    public boolean validate(byte[] bytes) {
        if (bytes == null)
            return false;
        int i = 0;
        for (; i + 7 < bytes.length; i += 8) {
            if ((((long) VH_LE_LONG.get(bytes, i)) & ASCII_MASK) != 0)
                return validateSlowPath(bytes, i);
        }
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return validateSlowPath(bytes, i);
        }
        return true;
    }
}
