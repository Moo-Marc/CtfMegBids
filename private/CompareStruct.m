function Message = CompareStruct(Old, New) %, TableToScalar
    % Message is 1xN (line).
    % TableToScalar true will cause entire columns (with differences) to be
    % printed on one line. Recommended for channels table, but not for
    % scans table. Now auto determined by size of table.
    %     if nargin < 3 || isempty(TableToScalar)
    %         TableToScalar = false;
    %     end
    if ~isstruct(New) || ~isstruct(Old)
        error('Expecting structure inputs.');
    elseif numel(New) ~= 1 || numel(Old) ~= 1
        error('Expecting scalar inputs.');
    end 
    OutFormat = '    %s: %s -> %s\n';
    Message = {};
    for Field = fieldnames(New)'
        Field = Field{1}; %#ok<FXSET>
        if ~isfield(Old, Field)
            Message{end+1} = sprintf(OutFormat, Field, '(none)', AutoSprintf(New.(Field)));
        elseif ~strcmp(class(Old.(Field)), class(New.(Field)))
            Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field))); % May not show the class change...
        else
            switch class(New.(Field))
                case {'double', 'datetime', 'logical'}
                    if any(size(Old.(Field)) ~= size(New.(Field))) || ...
                            any(~isequal(Old.(Field)(:), New.(Field)(:)))
                        Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                    end
                case 'char'
                    if any(size(Old.(Field)) ~= size(New.(Field))) || ...
                            ~strcmp(Old.(Field)(:), New.(Field)(:))
                        Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                    end
                case 'cell'
                    if any(size(Old.(Field)) ~= size(New.(Field)))
                        Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                    elseif iscellstr(New.(Field)) 
                        if ~isempty(setxor(Old.(Field)(:), New.(Field)(:)))
                            Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                        end
                    else % Not strings, same sizes.
                        % Could loop on cells here. 
                        % Try converting to "table-like" struct, by columns. This could give errors.
                        CellNames = arrayfun(@(x)sprintf('CellColumn%d',x), 1:size(New.(Field), 2));
                        Message = [Message, CompareStruct(cell2struct(Old.(Field), CellNames, 2), cell2struct(New.(Field), CellNames, 2))];
                    end
                case 'struct'
                    if numel(Old.(Field)) ~= numel(New.(Field))
                        % Just give overview of size difference.
                        Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                    else
                        for s = 1:numel(New.(Field))
                            Message = [Message, CompareStruct(Old.(Field)(s), New.(Field)(s))];
                        end
                    end
                case 'table'
                    if numel(Old.(Field).Properties.VariableNames) ~= numel(New.(Field).Properties.VariableNames)
                        % Just give overview of size difference.
                        Message{end+1} = sprintf(OutFormat, Field, AutoSprintf(Old.(Field)), AutoSprintf(New.(Field)));
                    else
                        % Only go into table line by line if small.
                        TableToScalar = size(New.(Field), 1) >= 10;
                        Message = [Message, CompareStruct(table2struct(Old.(Field), 'ToScalar', TableToScalar), table2struct(New.(Field), 'ToScalar', TableToScalar))];
                    end
                otherwise
                    error('Unsupported class %s', class(New.(Field)));
            end
        end
    end
end
