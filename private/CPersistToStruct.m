function [S, iEnd] = CPersistToStruct(C, iStart)
    % Convert CPersist file content to Matlab structure.
    %
    % Marc Lalancette, 2020
    
    S = [];
    if nargin < 2
        iStart = 1;
    end
    i = iStart;
    nC = numel(C);
    while i < nC
        switch C(i).name
            case 'WS1_'
                if i ~= iStart
                    error('Unexpected sub-struct start. i=%d', i);
                end
                % Do nothing.
            case 'EndOfParameters'
                iEnd = i;
                return
            otherwise
                if i < nC-1 && strcmp(C(i+1).name, 'WS1_')
                    % Should be type 2: substructure, but seems can be
                    % other types (1 custom, 14 long, ...).
                    %                     if C(i).type == 1 && isempty(C(i).data) % Custom, can be sub-structure
                    %                         [S.(Trim(C(i).name)), iEnd] = CPersistToStruct(C, i+1);
                    %                         i = iEnd;
                    %                     elseif C(i).type == 2 % Sub-structure array, size in data
                    if isempty(C(i).data)
                        nSub = 1;
                    else
                        nSub = C(i).data;
                    end
                    SubName = Trim(C(i).name);
                    for iSub = 1:nSub
                        [S.(SubName)(iSub), iEnd] = CPersistToStruct(C, i+1);
                        i = iEnd;
                    end
                    %                     end
                else
                    S.(Trim(C(i).name)) = C(i).data;
                end
        end
        i = i + 1;
    end
end

% Previous recursive implementation (didn't properly deal with sub structure arrays).
% function [S, iEnd] = CPersistToStruct(C, iStart)
%     if nargin < 2
%         iStart = 1;
%     end
%     i = iStart;
%     while i < numel(C)
%         switch C(i).name
%             case 'WS1_'
%                 if i > 1 
%                     if strcmp(C(i-1).name, 'EndOfParameters') || ...
%                             ~isempty(C(i-1).data)
%                         [S.(sprintf('NoNameField_%03d', i)), iEnd] = ...
%                             CPersistToStruct(C, i+1);
%                     else
%                         [S.(Trim(C(i-1).name)), iEnd] = CPersistToStruct(C, i+1);
%                     end
%                     i = iEnd + 1;
%                 else
%                     i = i + 1;
%                 end
%             case 'EndOfParameters'
%                 iEnd = i;
%                 return
%             otherwise
%                 S.(Trim(C(i).name)) = C(i).data;
%                 i = i + 1;
%         end
%     end
% end

function Str = Trim(Str)
    while ismember(Str(1), {'_', ' '})
        Str(1) = '';
    end
    while ismember(Str(end), {'_', ' '})
        Str(end) = '';
    end
end