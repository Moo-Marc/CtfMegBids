function DT = StrToDatetime(Str, Format)
    % 'n/a' will become NaT
    if isempty(Str)
        DT = datetime.empty(0);
        return;
    end
    if nargin < 2 || isempty(Format)
        Format = 'yyyy-MM-dd''T''HH:mm:ss';
    end
    if ischar(Str)
        Str = cellstr(Str);
    end
    Str(strcmpi(Str, 'n/a')) = {''};
    % Remove fraction of seconds (nanoseconds in mri!)
    iDot = strfind(Str, '.');
    %iColon = strfind(Str, ':');
    for iStr = 1:numel(Str)
        if ~isempty(iDot{iStr})
            Str{iStr}(iDot{iStr}(1):end) = '';
        end
        %if numel(iColon{iStr}) == 1
        %    Str{iStr} = [Str{iStr}, ':00'];
        %end
    end
    DT = datetime(Str, 'InputFormat', Format);
end
