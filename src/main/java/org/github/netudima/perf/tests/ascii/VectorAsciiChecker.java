package org.github.netudima.perf.tests.ascii;

import jdk.incubator.vector.ByteVector;
import jdk.incubator.vector.VectorMask;
import jdk.incubator.vector.VectorSpecies;
import org.openjdk.jmh.annotations.CompilerControl;

public class VectorAsciiChecker implements AsciiChecker {

    private static final VectorSpecies<Byte> SPECIES = ByteVector.SPECIES_PREFERRED;

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        int i = 0;
        int limit = SPECIES.loopBound(bytes.length);
        for (; i < limit; i += SPECIES.length()) {
            ByteVector v = ByteVector.fromArray(SPECIES, bytes, i);
            // any byte with high bit set (i.e. < 0 as signed) means non-ASCII
            VectorMask<Byte> nonAscii = v.lt((byte) 0);
            if (nonAscii.anyTrue())
                return false;
        }
        // scalar tail
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return false;
        }
        return true;
    }
}
