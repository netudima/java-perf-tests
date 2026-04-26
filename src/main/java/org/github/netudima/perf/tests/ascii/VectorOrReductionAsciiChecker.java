package org.github.netudima.perf.tests.ascii;

import jdk.incubator.vector.ByteVector;
import jdk.incubator.vector.VectorOperators;
import jdk.incubator.vector.VectorSpecies;
import org.openjdk.jmh.annotations.CompilerControl;

public class VectorOrReductionAsciiChecker implements AsciiChecker {

    private static final VectorSpecies<Byte> SPECIES = ByteVector.SPECIES_PREFERRED;

    @Override
    @CompilerControl(CompilerControl.Mode.PRINT)
    public boolean isAscii(byte[] bytes) {
        int i = 0;
        int limit = SPECIES.loopBound(bytes.length);
        byte acc = 0;
        // OR-reduce all lanes into a single byte — one branch per vector width
        for (; i < limit; i += SPECIES.length()) {
            acc |= ByteVector.fromArray(SPECIES, bytes, i)
                             .reduceLanes(VectorOperators.OR);
        }
        if (acc < 0)
            return false;
        // scalar tail
        for (; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return false;
        }
        return true;
    }
}
