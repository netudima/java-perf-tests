package org.github.netudima.perf.tests.ascii;

import org.openjdk.jmh.annotations.*;
import org.openjdk.jmh.infra.Blackhole;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 3, time = 5, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@Fork(1)
@Threads(1)
@State(Scope.Benchmark)
public class AsciiCheckerBenchmark {

    @Param({"simple", "swar"})
    public String checkerName;

    @Param({"short ASCII", "long ASCII", "short ASCII prefix non-ASCII", "short non-ASCII", "long non-ASCII"})
    public String stringType;

    private byte[] value;

    private AsciiChecker checker;

    @Setup(Level.Trial)
    public void setup() {
        value = switch (stringType) {
            case "short ASCII" -> "ASCII string".getBytes(StandardCharsets.UTF_8);
            case "long ASCII" -> ("ASCII is an acronym for American Standard Code for Information Interchange, " +
                                  "is a character encoding standard for representing a particular set of 95 " +
                                  "(English language focused) printable and 33 control characters – a total of 128 code points. " +
                                  "The set of available punctuation had significant impact on the syntax of computer languages " +
                                  "and text markup. ASCII hugely influenced the design of character sets used by modern computers; " +
                                  "for example, the first 128 code points of Unicode are the same as ASCII.").getBytes(StandardCharsets.UTF_8);
            case "short ASCII prefix non-ASCII" -> "a hierarchy of number systems: ℕ ⊆ ℕ₀ ⊂ ℤ ⊂ ℚ ⊂ ℝ ⊂ ℂ".getBytes(StandardCharsets.UTF_8);
            case "short non-ASCII" -> "ℕ ⊆ ℕ₀ ⊂ ℤ ⊂ ℚ ⊂ ℝ ⊂ ℂ".getBytes(StandardCharsets.UTF_8);
            case "long non-ASCII" -> ("⡍⠜⠇⠑⠹ ⠺⠁⠎ ⠙⠑⠁⠙⠒ ⠞⠕ ⠃⠑⠛⠔ ⠺⠊⠹⠲ ⡹⠻⠑ ⠊⠎ ⠝⠕ ⠙⠳⠃⠞\n" +
                                      "  ⠱⠁⠞⠑⠧⠻ ⠁⠃⠳⠞ ⠹⠁⠞⠲ ⡹⠑ ⠗⠑⠛⠊⠌⠻ ⠕⠋ ⠙⠊⠎ ⠃⠥⠗⠊⠁⠇ ⠺⠁⠎\n" +
                                      "  ⠎⠊⠛⠝⠫ ⠃⠹ ⠹⠑ ⠊⠇⠻⠛⠹⠍⠁⠝⠂ ⠹⠑ ⠊⠇⠻⠅⠂ ⠹⠑ ⠥⠝⠙⠻⠞⠁⠅⠻⠂\n" +
                                      "  ⠁⠝⠙ ⠹⠑ ⠡⠊⠑⠋ ⠍⠳⠗⠝⠻⠲ ⡎⠊⠗⠕⠕⠛⠑ ⠎⠊⠛⠝⠫ ⠊⠞⠲ ⡁⠝⠙\n" +
                                      "  ⡎⠊⠗⠕⠕⠛⠑⠰⠎ ⠝⠁⠍⠑ ⠺⠁⠎ ⠛⠕⠕⠙ ⠥⠏⠕⠝ ⠰⡡⠁⠝⠛⠑⠂ ⠋⠕⠗ ⠁⠝⠹⠹⠔⠛ ⠙⠑ \n" +
                                      "  ⠡⠕⠎⠑ ⠞⠕ ⠏⠥⠞ ⠙⠊⠎ ⠙⠁⠝⠙ ⠞⠕⠲").getBytes(StandardCharsets.UTF_8);
            default -> throw new IllegalArgumentException("Unknown stringType: " + stringType);
        };

        checker = switch (checkerName) {
            case "simple" -> new SimpleAsciiChecker();
            case "swar"   -> new SwarAsciiChecker();
            default -> throw new IllegalArgumentException("Unknown checker: " + checkerName);
        };
    }

    @Benchmark
    public void isAscii(Blackhole bh) {
        bh.consume(checker.isAscii(value));
    }
}
