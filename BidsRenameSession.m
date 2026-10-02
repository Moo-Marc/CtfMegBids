function BidsRenameSession(BidsSubjectFolder, OldNamePart, NewNamePart, isFull)
    % Rename a session ID in a CTF BIDS subject folder (and matching in sub-datasets).
    %
    % Name parts should not contain "ses-"
    % isFull true means the full session name (after ses-) is provided, instead of just part.
    %
    % Renames files, folders, inside BIDS scans.tsv and inside raw data files. Includes elsewhere in
    % potential "sub-datasets": sourcedata, derivatives, extras, etc. 
    % This also tries to rename inside json files (_meg.json AssociatedEmptyRoom, _coordsystem.json
    % DigitizedHeadPoints) and warns if fails, in which case it requires running BidsRebuildAllFiles
    % after.
    %
    % Marc Lalancette 2026-09-22

    if BidsSubjectFolder(end) == filesep
        warning('Removing training slash in subject folder.');
        BidsSubjectFolder(end) = '';
    end
    [BidsFolder, Subject] = fileparts(BidsSubjectFolder);
    if ~contains(Subject, 'sub-')
        error('Expecting BIDS subject folder (sub-...), got %s', Subject);
    end

    if nargin < 4 || isempty(isFull)
        isFull = false;
    end

    % Variables to make this function more similar to BidsRenameSubject, 
    % to make easier to maintain (and possibly to merge them at some point).
    Entity = 'ses-';
    RootFolder = BidsSubjectFolder;

    if isFull
        % Since this is "full", end with underscore (in file names) or slash (in paths)
        % (This works with path and file in same replace command.)
        OldExpr = [Entity OldNamePart '([_' filesep ']|$)'];
        NewExpr = [Entity NewNamePart '$1'];
        AfterExpr = [Entity NewNamePart '(?:[_' filesep ']|$)'];
        % Include prefix to simplify code.
        OldNameMask = ['*' Entity OldNamePart];
        NewNameMask = ['*' Entity NewNamePart];
    else
        if contains(NewNamePart, OldNamePart)
            error('Cannot rename with old name as part of the new name without "isFull".');
        end
        OldExpr = [Entity '([a-zA-Z0-9]*)' OldNamePart '([a-zA-Z0-9]*)([_' filesep ']|$)'];
        NewExpr = [Entity '$1', NewNamePart, '$2$3'];
        AfterExpr = [Entity '[a-zA-Z0-9]*' NewNamePart '[a-zA-Z0-9]*(?:[_' filesep ']|$)'];
        OldNameMask = ['*' Entity '*' OldNamePart '*'];
        NewNameMask = ['*' Entity '*' NewNamePart '*'];
    end

    % Verify if unique, and if new exists.
    if isFull
        List = dir(fullfile(RootFolder, [OldNameMask, '*'])); % last * to avoid listing contents
    else
        List = RegexpDir(fullfile(RootFolder, OldNameMask), OldExpr);
    end
    List(~[List.isdir]) = [];
    if isempty(List)
        warning('Session not found: %s/%s', RootFolder, OldNameMask);
        return;
    elseif numel(List) > 1
        error('Multiple matches %s/%s', List.folder, OldNameMask);
    else
        NewS = regexprep(List.name, OldExpr, NewExpr); 
        if exist(fullfile(List.folder, NewS), 'dir')
            error('New session name already exists: %s', fullfile(List.folder, NewS));
        end
    end
    
    % Rename recordings first, including inside some data files (infods, res4, xml, etc.).
    List = RegexpDir(fullfile(RootFolder, '**', [OldNameMask '_*.ds']), OldExpr);
    for f = 1:numel(List)
        Recording = fullfile(List(f).folder, List(f).name);
        Bids_ctf_rename_ds(Recording, regexprep(List(f).name, OldExpr, NewExpr));
    end

    % Rename other files.
    List = RegexpDir(fullfile(RootFolder, '**', [OldNameMask '_*']), OldExpr);
    List([List.isdir]) = [];
    for f = 1:numel(List)
        [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
            fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr)));
        if ~IsOk, error(Message); end
    end

    % Rename folders after, inverse list order so that subfolders
    % (datasets) are renamed before their parents (subject folders).
    List = RegexpDir(fullfile(RootFolder, '**', OldNameMask), OldExpr);
    % Remove files
    List(~[List.isdir]) = [];
    for f = numel(List):-1:1
        CurrentFolder = fullfile(List(f).folder, List(f).name);
        NewFolder = fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr));
        [IsOk, Message] = movefile(CurrentFolder, NewFolder);
        if ~IsOk, error(Message); end
    end

    % Rename metadata inside BIDS scans.tsv files.
    List = RegexpDir(fullfile(RootFolder, '**', [NewNameMask '_scans.tsv']), AfterExpr); % could be more specific here, but it works.
    for f = 1:numel(List) % Only 1 expected per session.
        ScansFile = fullfile(List(f).folder, List(f).name);
        Fid = fopen(ScansFile, 'r');
        ScansText = fread(Fid, '*char')';
        fclose(Fid);
        if ~isempty(regexp(ScansText, OldExpr, 'once'))
            ScansText = regexprep(ScansText, OldExpr, NewExpr);
            Fid = fopen(ScansFile, 'w');
            fprintf(Fid, '%s', ScansText);
            fclose(Fid);
        end
    end

    % Rename inside coordsystem.json, but keep coreg, don't just recreate everything by default.
    List = RegexpDir(fullfile(RootFolder, '**', [NewNameMask '_*coordsystem.json']), AfterExpr);
    for f = 1:numel(List) % Only 1 expected per session.
        CoordFile = fullfile(List(f).folder, List(f).name);
        J = JsonRead(CoordFile);
        isChanged = false;
        if isfield(J, 'DigitizedHeadPoints')
            OldPos = J.DigitizedHeadPoints;
            J.DigitizedHeadPoints = regexprep(J.DigitizedHeadPoints, OldExpr, NewExpr);
            if ~strcmp(OldPos, J.DigitizedHeadPoints) % otherwise no change, move on.
                NewPosFull = fullfile(List(f).folder, J.DigitizedHeadPoints);
                % Verify the renamed file exists.
                if ~exist(NewPosFull, 'file')
                    if exist(fullfile(List(f).folder, OldPos), 'file')
                        warning('Renamed head points file not found: %s , keeping original in _coordsystem.json: %s', NewPosFull, OldPos);
                        J.DigitizedHeadPoints = OldPos;
                    else
                        warning('Renamed head points file not found: %s , investigate and fix.', NewPosFull);
                        isChanged = true;
                    end
                else
                    isChanged = true;
                end
            end
        end
        if isfield(J, 'IntendedFor')
            % This can be in a different session and not need renaming, but try.
            if iscell(J.IntendedFor)
                for iCell = 1:length(J.IntendedFor)
                    Prev = J.IntendedFor{iCell};
                    J.IntendedFor{iCell} = regexprep(J.IntendedFor{iCell}, OldExpr, NewExpr);
                    if strcmp(Prev, J.IntendedFor{iCell})
                        % No change, likely in another session.
                        continue; % cell loop
                    end
                    FullFile = process_import_bids('ResolveBidsUri', J.IntendedFor{iCell}, BidsFolder);
                    if ~exist(FullFile, 'file')
                        warning('Renamed "intended for" file not found: %s , investigate and fix.', FullFile);
                    end
                    isChanged = true;
                end
            else
                Prev = J.IntendedFor;
                J.IntendedFor = regexprep(J.IntendedFor, OldExpr, NewExpr);
                if ~strcmp(Prev, J.IntendedFor)
                    FullFile = process_import_bids('ResolveBidsUri', J.IntendedFor, BidsFolder);
                    if ~exist(FullFile, 'file')
                        warning('Renamed "intended for" file not found: %s , investigate and fix.', FullFile);
                    end
                    isChanged = true;
                end
            end
        end
        if isChanged
            % Save modified json file.
            WriteJson(CoordFile, J);
        end
    end

    % Rename inside _meg.json.
    List = RegexpDir(fullfile(RootFolder, '**', [NewNameMask '_*meg.json']), AfterExpr);
    for f = 1:numel(List) % One per recording, except "noise".
        MegJsonFile = fullfile(List(f).folder, List(f).name);
        J = JsonRead(MegJsonFile);
        isChanged = false;
        if isfield(J, 'AssociatedEmptyRoom')
            Prev = J.AssociatedEmptyRoom;
            J.AssociatedEmptyRoom = regexprep(J.AssociatedEmptyRoom, OldExpr, NewExpr);
            if ~strcmp(Prev, J.AssociatedEmptyRoom)
                FullFile = process_import_bids('ResolveBidsUri', J.AssociatedEmptyRoom, BidsFolder);
                if ~exist(FullFile, 'file')
                    warning('Renamed "associated empty room" file not found: %s , investigate and fix.', FullFile);
                end
                isChanged = true;
            end
        end
        if isChanged
            % Save modified json file.
            WriteJson(MegJsonFile, J);
        end
    end


    %     SubDatasets = {'sourcedata', 'derivatives', 'extras'};
    % last * to avoid listing directory contents, including . and ..
    MatchingFolders = dir(fullfile(BidsFolder, '*', [Subject '*'])); % trailing * to avoid listing contents
    MatchingFolders(~[MatchingFolders.isdir]) = [];

    for iSubD = 1:numel(MatchingFolders)
        % Call recursively
        BidsRenameSession(fullfile(MatchingFolders(iSubD).folder, MatchingFolders(iSubD).name), ...
            OldNamePart, NewNamePart, isFull);
    end

    %___________________________________________________________________________________
    % List files based on wildcards, and filter using a more specific regular expression.
    % In some cases when "isFull", the filter is not needed, but sometimes it is, so we just do it.
    function List = RegexpDir(Mask, Expr)
        List = dir(Mask);
        for i = numel(List):-1:1
            if isempty(regexp(List(i).name, Expr, 'once'))
                List(i) = [];
            end
        end
    end

end
