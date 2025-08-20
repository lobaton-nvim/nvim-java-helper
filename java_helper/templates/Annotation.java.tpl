package ${PACKAGE};

import java.lang.annotation.*;

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface ${NAME} {
    String value();
}
