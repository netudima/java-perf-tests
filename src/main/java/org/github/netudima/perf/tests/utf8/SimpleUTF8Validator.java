package org.github.netudima.perf.tests.utf8;

public class SimpleUTF8Validator extends BaseUTF8Validator {

    @Override
    public boolean validate(byte[] bytes) {
        if (bytes == null)
            return false;
        for (int i = 0; i < bytes.length; i++) {
            if (bytes[i] < 0)
                return validateSlowPath(bytes, i);
        }
        return true;
    }
}
