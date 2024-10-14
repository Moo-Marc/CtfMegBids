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
    elseif Type < 7 && exist(fullfile(Destination, List(iL).name), 'file')
        % When merging within a session, it's expected that the updated source scans.tsv will
        % overwrite the destination scans.tsv here.
        if strcmpi(List(iL).name(end-9:end), '_scans.tsv')
            [isOk, Message] = movefile(Item, Destination);
            if ~isOk, return; end
        else
            % We are being extra careful here, but in some cases we may have the same file on both
            % sides and it would be ok to move it.
            error('File already exists in destination: %s', fullfile(Destination, List(iL).name));
        end
    elseif ~exist(fullfile(Destination, List(iL).name), 'file') % new file or new folder
        [isOk, Message] = movefile(Item, Destination);
        if ~isOk, return; end
    else % folder existing in destination
        % Recurse.
        [isOk, Message] = mergefile(fullfile(Item, '*'), fullfile(Destination, List(iL).name));
        if ~isOk, return; end
        if ~isfolder(Item)
            error('Expecting folder: %s', Item);
        elseif numel(dir(Item)) > 2
            warning('Seems folder is not empty: %s', Item);
        end
        [isOk, Message] = rmdir(Item);
        if ~isOk, return; end
    end
end
end