if status is-interactive
    # Commands to run in interactive sessions can go here
end

set fish_greeting


function fish_prompt
    # Arch logo (Cyan)
    set_color 
    echo -n " "

    # Home icon + Tilde path (Cyan)
    #set_color 
    #echo -n "  "

    # Print full current working directory path
    echo -n (pwd | string replace -r "^$HOME" "~")
    echo -n " "

    # Prompt arrow
    set_color 
    echo -n "❮ "

    set_color normal
end
