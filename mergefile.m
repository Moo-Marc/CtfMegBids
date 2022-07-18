function [isOk, Message] = mergefile(Source, Destination)
% Move files and folders recursively without complaining of existing destination folders.
% List all files and folders, if wildcards were used.
List = dir(Source);
for iL = 1:numel(List)
    if any(strcmp(List(iL).name, {'.', '..'}))
        continue;
    end
    Item = fullfile(List(iL).folder, List(iL).name);
    Type = exist(Item, 'file');
    if ~Type % disappeared
        error('Not found: %s', Item);
    elseif Type < 7 || ~exist(fullfile(Destination, List(iL).name), 'file') % file or new folder
        [isOk, Message] = movefile(Item, Destination);
        if ~isOk, return; end
    else % folder existing in destination
        % Recurse.
        [isOk, Message] = mergefile(fullfile(Item, '*'), fullfile(Destination, List(iL).name));
        if ~isOk, return; end
        rmdir(Item);
    end
end
end