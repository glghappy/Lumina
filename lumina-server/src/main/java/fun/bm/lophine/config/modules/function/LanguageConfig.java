package fun.bm.lophine.config.modules.function;

import fun.bm.lophine.utils.ServerI18nUtil;
import me.earthme.luminol.config.flags.ConfigClassInfo;
import me.earthme.luminol.config.flags.ConfigInfo;
import me.earthme.luminol.config.flags.NeedRun;
import me.earthme.luminol.enums.EnumConfigCategory;
import me.earthme.luminol.enums.EnumRunnableType;

@ConfigClassInfo(category = EnumConfigCategory.FUNCTION, name = "language")
public class LanguageConfig {
    @ConfigInfo(name = "lang")
    public static String lang = "en_us";

    @ConfigInfo(name = "full_blocking_load")
    public static boolean full_blocking_load = false;

    @ConfigInfo(name = "allow_auto_reset_comments")
    public static boolean allowAutoResetComments = true;

    @NeedRun(when = EnumRunnableType.ON_LOADED)
    public void reloadLanguage() {
        if (ServerI18nUtil.isInit()) {
            ServerI18nUtil.reload();
        }
    }
}