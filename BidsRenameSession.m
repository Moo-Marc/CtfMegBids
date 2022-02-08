function BidsRenameSession(BidsSubjectFolder, OldNamePart, NewNamePart)
    % Rename a session ID in a CTF BIDS subject folder (and matching in sub-datasets).
    %
    % Files, folders, in some data files. Also look for other potential
    % sub-datasets: derivatives, sourcedata, extras, etc.
    % Marc Lalancette 2022-02-07
    
    [BidsFolder, Subject] = fileparts(BidsSubjectFolder);
    if ~contains(Subject, 'sub-')
        error('Expecting BIDS subject folder (sub-...), got %s', Subject);
    end
    
    OldExpr = ['ses-([a-zA-Z0-9]*)', OldNamePart, '([a-zA-Z0-9]*)_'];
    NewExpr = ['ses-$1', NewNamePart, '$2_'];

    % Rename recordings first, including inside some data files.
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*.ds']));
    for f = 1:numel(List)
        Bids_ctf_rename_ds(fullfile(List(f).folder, List(f).name), ...
            regexprep(List(f).name, OldExpr, NewExpr));
    end

    % Rename other files.
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*']));
    List([List.isdir]) = [];
    for f = 1:numel(List)
        [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
            fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr)));
        if ~IsOk
            error(Message);
        end
    end
    
    % Rename folders after, inverse list order so that subfolders
    % are renamed before their parents.
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*']));
    List(~[List.isdir]) = [];
    for f = numel(List):-1:1
        if List(f).isdir
            [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
                fullfile(List(f).folder, regexprep(List(f).name, OldExpr(1:end-1), NewExpr(1:end-1)))); % don't include ending _ for folders
            if ~IsOk
                error(Message);
            end
        end
    end

    % Rename metadata inside BIDS scans.tsv files.
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', NewNamePart, '*_scans.tsv']));
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
    
    %     SubDatasets = {'sourcedata', 'derivatives', 'extras'};
    % last * to avoid listing directory contents, including . and ..
    MatchingFolders = dir(fullfile(BidsFolder, '*', [Subject '*'])); 
    MatchingFolders(~[MatchingFolders.isdir]) = [];
    
    for iSubD = 1:numel(MatchingFolders)
        % Call recursively
        BidsRenameSession(fullfile(MatchingFolders.folder, MatchingFolders.name), ...
            OldNamePart, NewNamePart);
    end
end