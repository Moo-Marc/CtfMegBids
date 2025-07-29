function BidsRenameSession(BidsSubjectFolder, OldNamePart, NewNamePart, isFull)
    % Rename a session ID in a CTF BIDS subject folder (and matching in sub-datasets).
    %
    % Name parts should not contain "ses-"
    % isFull true means the full session name is provided, instead of just
    % part.
    %
    % This now tries to rename inside json files (_meg.json AssociatedEmptyRoom, _coordsystem.json
    % DigitizedHeadPoints) and warns if fails, in which case it requires running BidsRebuildAllFiles
    % after.
    %
    % Files, folders, in some data files. Also looks in other potential sub-datasets: derivatives,
    % sourcedata, extras, etc.
    %
    % Marc Lalancette 2024-10-09

    [BidsFolder, Subject] = fileparts(BidsSubjectFolder);
    if ~contains(Subject, 'sub-')
        error('Expecting BIDS subject folder (sub-...), got %s', Subject);
    end

    if nargin < 4 || isempty(isFull)
        isFull = false;
    end
    if isFull
        OldExpr = ['ses-', OldNamePart, '_'];
        NewExpr = ['ses-', NewNamePart, '_'];
    else
        if contains(NewNamePart, OldNamePart)
            error('Cannot rename with old name as part of the new name without "isFull".');
        end
        OldExpr = ['ses-([a-zA-Z0-9]*)', OldNamePart, '([a-zA-Z0-9]*)_'];
        NewExpr = ['ses-$1', NewNamePart, '$2_'];
    end

    % Verify if unique, and if new session exists.
    if isFull
        List = dir(fullfile(BidsSubjectFolder, ['ses-', OldNamePart, '*'])); % last * to avoid listing contents
    else
        %List = dir(fullfile(BidsSubjectFolder, ['ses-*', OldNamePart, '*']));
        List = RegexpDir(fullfile(BidsSubjectFolder, ['ses-*', OldNamePart, '*']), OldExpr);
    end
    List(~[List.isdir]) = [];
    if isempty(List)
        if isFull
            warning('Session not found: %s/ses-%s', BidsSubjectFolder, OldNamePart);
        else
            warning('Session not found: %s/ses-*%s*', BidsSubjectFolder, OldNamePart);
        end
        return;
    elseif numel(List) > 1
        error('Multiple sessions match %s/ses-*%s*', List.folder, OldNamePart);
    else
        NewSes = regexprep(List.name, OldExpr(1:end-1), NewExpr(1:end-1)); % don't include ending _ for folders
        if exist(fullfile(List.folder, NewSes), 'dir')
            error('New session name already exists: %s', fullfile(List.folder, NewSes));
        end
    end

    % Rename recordings first, including inside some data files.
    if isFull
        RecList = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '_*.ds']));
    else
        %List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*.ds']));
        RecList = RegexpDir(fullfile(BidsSubjectFolder, ['ses-*', OldNamePart, '*_*.ds']), OldExpr);
    end
    for f = 1:numel(RecList)
        Recording = fullfile(RecList(f).folder, RecList(f).name);
        Bids_ctf_rename_ds(Recording, regexprep(RecList(f).name, OldExpr, NewExpr));
    end

    % Rename other files.
    if isFull
        List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '_*']));
    else
        %List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*']));
        List = RegexpDir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*']), OldExpr);
    end
    List([List.isdir]) = [];
    for f = 1:numel(List)
        [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
            fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr)));
        if ~IsOk, error(Message); end
    end

    % Rename folders after, inverse list order so that subfolders
    % are renamed before their parents.
    if isFull
        % The session folder itself
        List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart]));
        % Others - though there shouldn't be any
        List = [List, dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '_*']))];
    else
        %List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*']));
        List = RegexpDir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*']), OldExpr);
    end
    List(~[List.isdir]) = [];
    for f = numel(List):-1:1
        if List(f).isdir
            [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
                fullfile(List(f).folder, regexprep(List(f).name, OldExpr(1:end-1), NewExpr(1:end-1)))); % don't include ending _ for folders
            if ~IsOk, error(Message); end
        end
    end

    % Rename metadata inside BIDS scans.tsv files.
    if isFull
        List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', NewNamePart, '_scans.tsv']));
    else
        %List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', NewNamePart, '*_scans.tsv']));
        List = RegexpDir(fullfile(BidsSubjectFolder, '**', ['*ses-*', NewNamePart, '*_scans.tsv']), OldExpr);
    end
    for f = 1:numel(List)
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

    % Rename inside meg.json and coordsystem.json
    for f = 1:numel(RecList)
        Recording = fullfile(RecList(f).folder, RecList(f).name);
        % Try getting sub, ses, task from dataset name.
        RecTok = split(RecList(f).name, '-_');
        if contains(Recording, 'sub-') && contains(Recording, '_ses-') && contains(Recording, '_task-') && ...
                numel(RecTok) > 6
            Overwrite = true;
            BidsInfo = [];
            BidsInfo.Subject = RecTok{2};
            BidsInfo.Session = RecTok{4};
            BidsInfo.Task = RecTok{6};
            BidsBuildRecordingFiles(Recording, BidsInfo, Overwrite);
        else
            warning('Unable to rename inside _meg.json and _coordsystem.json files for recording %.', Recording);
        end
    end

    %     SubDatasets = {'sourcedata', 'derivatives', 'extras'};
    % last * to avoid listing directory contents, including . and ..
    MatchingFolders = dir(fullfile(BidsFolder, '*', [Subject '*']));
    MatchingFolders(~[MatchingFolders.isdir]) = [];

    for iSubD = 1:numel(MatchingFolders)
        % Call recursively
        BidsRenameSession(fullfile(MatchingFolders(iSubD).folder, MatchingFolders(iSubD).name), ...
            OldNamePart, NewNamePart, isFull);
    end
end

function List = RegexpDir(Mask, Expr)
    List = dir(Mask);
    for i = numel(List):-1:1
        if isempty(regexp(List(i).name, Expr, 'once'))
            List(i) = [];
        end
    end
end
