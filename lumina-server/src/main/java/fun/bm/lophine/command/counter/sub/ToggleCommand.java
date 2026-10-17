package fun.bm.lophine.command.counter.sub;

import com.mojang.brigadier.arguments.BoolArgumentType;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import fun.bm.lophine.command.counter.CounterSubCommand;
import fun.bm.lophine.utils.ServerI18nUtil;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.jetbrains.annotations.NotNull;
import org.leavesmc.leaves.command.ArgumentNode;
import org.leavesmc.leaves.command.CommandContext;
import org.leavesmc.leaves.util.HopperCounter;

public class ToggleCommand extends CounterSubCommand {
    public ToggleCommand() {
        super("toggle");
        children(
                BooleanArg::new
        );
    }

    @Override
    protected boolean execute(@NotNull CommandContext context) throws CommandSyntaxException {
        boolean newValue = !HopperCounter.isEnabled();
        HopperCounter.setEnabled(newValue);
        context.getSender().sendMessage(Component.text(ServerI18nUtil.getLocalizedText("lophine.command.counter.toggle.now." + newValue), newValue ? NamedTextColor.AQUA : NamedTextColor.RED));
        return true;
    }

    private static class BooleanArg extends ArgumentNode<Boolean> {
        protected BooleanArg() {
            super("enabled", BoolArgumentType.bool());
        }

        @Override
        protected boolean execute(@NotNull CommandContext context) {
            boolean enabled = context.getArgument(BooleanArg.class);
            if (enabled == HopperCounter.isEnabled()) {
                context.getSender().sendMessage(Component.text(ServerI18nUtil.getLocalizedText("lophine.command.counter.toggle.already." + enabled), NamedTextColor.GRAY));
            } else {
                HopperCounter.setEnabled(enabled);
                context.getSender().sendMessage(Component.text(ServerI18nUtil.getLocalizedText("lophine.command.counter.toggle.now." + enabled), enabled ? NamedTextColor.AQUA : NamedTextColor.RED));
            }
            return true;
        }
    }
}
