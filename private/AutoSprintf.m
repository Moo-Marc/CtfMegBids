function Str = AutoSprintf(Var)
    if isempty(Var)
        Str = '(none)';
        return;
    end
    switch class(Var)
        case {'double', 'logical'}
            Str = mat2str(Var, 5);
            %             Str = sprintf('%g ', Var(:));
            %             Str(end) = '';
        case 'char'
            Str = ['''', Var, ''''];
        case 'datetime'
            Str = sprintf('%s ', Var(:)); % auto convert to string
            Str(end) = '';
        case 'cell'
            if iscellstr(Var)
                Str = Var{1};
                for c = 2:numel(Var)
                    Str = [Str, ' ', Var{c}];
                end
            else
                Str = sprintf('(non-string cell %s)', AutoSprintf(size(Var)));
            end
        otherwise
            Str = sprintf('(%s %s)', class(Var), AutoSprintf(size(Var)));
    end
end
