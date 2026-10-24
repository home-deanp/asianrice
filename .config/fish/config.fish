if status is-interactive
    fish_vi_key_bindings
    function fish_mode_prompt
    end

    function fish_user_key_bindings
        # Bind Ctrl+R to history search in Insert mode
        bind -M insert \cr history-pager
        # Bind Ctrl+R to history search in Normal mode
        bind -M default \cr history-pager
    end

    set -gx EDITOR nvim
    set fish_greeting

    function fish_prompt
        set -l last_status $status

        # Top Line: ╭─ username@hostname  ~/path
        set_color blue
        echo -n "╭─ "
        set_color cyan
        echo (string join "" $USER "@" (prompt_hostname) "  " (pwd | string replace -r "^$HOME" "~"))

        # Bottom Line: ╰─❯
        set_color blue
        echo -n "╰─"
        set_color cyan
        echo -n "❯ "
        set_color normal
    end
end
