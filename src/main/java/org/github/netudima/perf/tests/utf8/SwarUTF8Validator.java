package org.github.netudima.perf.tests.utf8;

import org.openjdk.jmh.annotations.CompilerControl;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.nio.ByteOrder;

public class SwarUTF8Validator extends BaseUTF8Validator {

    private static final long ASCII_MASK = 0x8080808080808080L;

    // byte order doesn't matter here
    private static final VarHandle VH_LE_LONG =
            MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean validate(byte[] bytes) {
        if (bytes == null)
            return false;
        if(validateAscii(bytes))
            return true;
        return validateSlowPath(bytes, 0);
    }

    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean validateAscii(byte[] bytes) {
        int i = 0;
        for (; i + 7 < bytes.length; i += 8) {
            if ((((long) VH_LE_LONG.get(bytes, i)) & ASCII_MASK) != 0)
                return false;
        }
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return false;
        }
        return true;
    }
}
