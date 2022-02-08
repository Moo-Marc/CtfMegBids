function Message = Compare(Old, New, Field) %, TableToScalar
    % Message is cell 1xN (line).
    % TableToScalar true will cause entire columns (with differences) to be
    % printed on one line. Recommended for channels table, but not for
    % scans table. Now auto determined by size of table.
    %     if nargin < 3 || isempty(TableToScalar)
    %         TableToScalar = false;
    %     end
    
    if nargin < 3 || isempty(Field)
        Field = '(root)';
    end
    OutFormat = '    %s: %s -> %s\n';
    Message = {};
    if ~strcmp(class(Old), class(New))
        Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))}; % May not show the class change...
        return;
    end
    switch class(New)
        % jsondecode reads vectors as columns.  Ignore size 1 when
        % comparing array sizes.
        case {'double', 'datetime', 'logical'}
            if any(setdiff(size(Old), 1) ~= setdiff(size(New), 1)) || any(~isequal(Old(:), New(:)))
                Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))};
            end
        case 'char'
            if any(size(Old) ~= size(New)) || ~strcmp(Old(:), New(:))
                Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))};
            end
        case 'cell'
            if any(setdiff(size(Old), 1) ~= setdiff(size(New), 1)) || ( iscellstr(New) && ~isempty(setxor(Old(:), New(:))) )
                Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))};
            elseif ~iscellstr(New) % Not strings, same sizes.
                % Could loop on cells here.
                % Try converting to "table-like" struct, by columns. This can give errors.
                CellNames = arrayfun(@(x)sprintf('CellColumn%d',x), 1:size(New, 2), 'UniformOutput', false);
                Message = Compare(cell2struct(Old, CellNames, 2), cell2struct(New, CellNames, 2), Field);
            end
        case 'struct'
            if any(setdiff(size(Old), [0,1]) ~= setdiff(size(New), [0,1]))
                % Just give overview of size difference.
                Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))};
            elseif numel(New) > 1
                if isempty(Old)
                    for s = 1:numel(New)
                        Message = [Message, Compare([], New(s), sprintf('%s(%d)', Field, s))];
                    end
                else
                    for s = 1:numel(New)
                        Message = [Message, Compare(Old(s), New(s), sprintf('%s(%d)', Field, s))];
                    end
                end
            else
                for Field = fieldnames(New)'
                    Field = Field{1}; %#ok<FXSET>
                    if ~isfield(Old, Field) || isempty(Old)
                        Message{end+1} = sprintf(OutFormat, Field, '(none)', AutoSprintf(New.(Field)));
                    else
                        Message = [Message, Compare(Old.(Field), New.(Field), Field)];
                    end
                end
            end
        case 'table'
            if numel(Old.Properties.VariableNames) ~= numel(New.Properties.VariableNames)
                % Just give overview of size difference.
                Message = {sprintf(OutFormat, Field, AutoSprintf(Old), AutoSprintf(New))};
            else
                % Only go into table line by line if small.
                TableToScalar = size(New, 1) >= 10;
                Message = Compare(table2struct(Old, 'ToScalar', TableToScalar), table2struct(New, 'ToScalar', TableToScalar), Field);
            end
        otherwise
            error('Unsupported class %s', class(New));
    end
end
