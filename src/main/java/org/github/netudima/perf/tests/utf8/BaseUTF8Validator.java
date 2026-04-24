package org.github.netudima.perf.tests.utf8;

// the logic is taken from org.apache.cassandra.serializers.UTF8Serializer
// to test it in isolation
abstract class BaseUTF8Validator implements UTF8Validator {

    private enum State {
        START,
        TWO,
        TWO_80,
        THREE_a0bf,
        THREE_80bf_1,
        THREE_80bf_2,
        FOUR_90bf,
        FOUR_80bf_3,
    }

    protected static boolean validateSlowPath(byte[] bytes, int offset) {
        int b;
        State state = State.START;
        while (offset < bytes.length) {
            b = bytes[offset++];
            switch (state) {
                case START:
                    if (b >= 0) {
                        if (b > 127)
                            return false;
                    } else if ((b >> 5) == -2) {
                        if (b == (byte) 0xc0)
                            state = State.TWO_80;
                        else if ((b & 0x1e) == 0)
                            return false;
                        else
                            state = State.TWO;
                    } else if ((b >> 4) == -2) {
                        if (b == (byte) 0xe0)
                            state = State.THREE_a0bf;
                        else
                            state = State.THREE_80bf_2;
                        break;
                    } else if ((b >> 3) == -2) {
                        if (b == (byte) 0xf0)
                            state = State.FOUR_90bf;
                        else
                            state = State.FOUR_80bf_3;
                        break;
                    } else {
                        return false;
                    }
                    break;
                case TWO:
                    if ((b & 0xc0) != 0x80)
                        return false;
                    state = State.START;
                    break;
                case TWO_80:
                    if (b != (byte) 0x80)
                        return false;
                    state = State.START;
                    break;
                case THREE_a0bf:
                    if ((b & 0xe0) == 0x80)
                        return false;
                    state = State.THREE_80bf_1;
                    break;
                case THREE_80bf_1:
                    if ((b & 0xc0) != 0x80)
                        return false;
                    state = State.START;
                    break;
                case THREE_80bf_2:
                    if ((b & 0xc0) != 0x80)
                        return false;
                    state = State.THREE_80bf_1;
                    break;
                case FOUR_90bf:
                    if ((b & 0x30) == 0)
                        return false;
                    state = State.THREE_80bf_2;
                    break;
                case FOUR_80bf_3:
                    if ((b & 0xc0) != 0x80)
                        return false;
                    state = State.THREE_80bf_2;
                    break;
                default:
                    return false;
            }
        }
        return state == State.START;
    }
}
