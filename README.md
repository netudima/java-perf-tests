# java-perf-tests

JMH microbenchmark project for comparing JVM performance across implementations and JDK versions.

## Requirements

- Maven 3.x
- JDK 17 (used to build)
- JDK 17 / 21 / 25 for running benchmarks (configure paths in `set-env.sh`)

## Setup

Copy the environment template and set your local JDK paths:

```bash
cp set-env.sh.template set-env.sh
# edit set-env.sh to point JDK_HOME_17/21/25 to your installations
```

## Building

```bash
mvn clean package
```

Produces `target/benchmarks.jar`.

## Running benchmarks

```bash
./run-benchmarks.sh [options] [benchmark-filter] [JMH args...]

Options:
  -p <name=value>   Pass a JMH @Param value (repeatable)
  -j <version>      JDK version: 17, 21, 25, or all (default: 21)
  -prof <profiler>  JMH profiler (e.g. xctraceasm, async, gc)
  -h                Show help
```

Examples:

```bash
# Run all benchmarks on JDK 21
./run-benchmarks.sh

# Run on all JDK versions
./run-benchmarks.sh -j all

# Filter by benchmark class
./run-benchmarks.sh AsciiCheckerBenchmark
./run-benchmarks.sh UTF8ValidatorBenchmark

# Filter by param values
./run-benchmarks.sh -p impl=swar -p 'stringType=long ASCII' AsciiCheckerBenchmark

# Run with a profiler
./run-benchmarks.sh -prof xctraceasm -p impl=swar AsciiCheckerBenchmark

# Run across all JDKs with a specific string type
./run-benchmarks.sh -j all -p 'stringType=long ASCII'
```

Each run saves output to `logs/<benchmark>-YYYYMMDD-HHMMSS.log`. If compiler assembly output is present, it is extracted into a separate `logs/<benchmark>-YYYYMMDD-HHMMSS-compiler.log`.

## Benchmarks

### ASCII checking (`org.github.netudima.perf.tests.ascii`)

Checks whether a byte array contains only ASCII characters.

| `impl` | Description |
|---|---|
| `simple` | Scalar loop with index (`bytes[i] < 0`) |
| `simple-foreach` | Scalar loop with foreach (`for (byte b : bytes)`) |
| `swar` | SWAR: 8 bytes at a time via `VarHandle` + `0x8080808080808080` mask |

**Params:** `impl`, `stringType`

### UTF-8 validation (`org.github.netudima.perf.tests.utf8`)

Validates whether a byte array is well-formed UTF-8. Logic derived from Apache Cassandra's `UTF8Serializer`, adapted to work directly on `byte[]`.

| `impl` | Description |
|---|---|
| `simple` | Scalar ASCII fast path + full UTF-8 state-machine slow path |
| `swar` | SWAR 8-bytes-at-a-time ASCII fast path + same slow path |

**Params:** `impl`, `stringType`

### String types

Both benchmarks use the same five `stringType` values:

| Value | Description |
|---|---|
| `short ASCII` | Short all-ASCII string |
| `long ASCII` | Long all-ASCII string (~450 bytes) |
| `short ASCII prefix non-ASCII` | Short string with ASCII prefix followed by non-ASCII |
| `short non-ASCII` | Short string starting with non-ASCII immediately |
| `long non-ASCII` | Long Braille Unicode string |
