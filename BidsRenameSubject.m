function BidsRenameSubject(BidsFolder, OldNamePart, NewNamePart, isFull, Verbose)
    % Rename a subject ID everywhere in a CTF MEG BIDS dataset.
    %
    % Files, folders, inside BIDS scans.tsv and inside raw data files. Includes
    % elsewhere in potential "sub-datasets": sourcedata, derivatives, extras,
    % etc. 
    %   
    % Marc Lalancette 2022-02-07

    if nargin < 5 || isempty(Verbose)
        Verbose = true;
    end
    if nargin < 4 || isempty(isFull)
        isFull = false;
    end
    if isFull
        OldExpr = ['sub-', OldNamePart, '_ses'];
        NewExpr = ['sub-', NewNamePart, '_ses'];
    else
        OldExpr = ['sub-([a-zA-Z0-9]*)', OldNamePart, '([a-zA-Z0-9]*)_ses'];
        NewExpr = ['sub-$1', NewNamePart, '$2_ses'];
    end

    % Rename recordings first, including inside raw data files (infods, res4, xml, etc.).
    if isFull
        List = dir(fullfile(BidsFolder, '**', ['*sub-', OldNamePart, '_ses*.ds']));
    else
        List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*_ses*.ds']));
    end
    for f = 1:numel(List)
        Bids_ctf_rename_ds(fullfile(List(f).folder, List(f).name), ...
            regexprep(List(f).name, OldExpr, NewExpr));
    end

    % Rename other files.
    if isFull
        List = dir(fullfile(BidsFolder, '**', ['*sub-', OldNamePart, '_ses*']));
    else
        List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*_ses*']));
    end
    List([List.isdir]) = [];
    for f = 1:numel(List)
        [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), ...
            fullfile(List(f).folder, regexprep(List(f).name, OldExpr, NewExpr)));
        if ~IsOk
            error(Message);
        end
    end
    
    % Rename folders after, inverse list order so that subfolders
    % (datasets) are renamed before their parents (subject folders).
    if isFull
        % Only subject (or maybe with _ right after?)
        List = dir(fullfile(BidsFolder, '**', ['*sub-', OldNamePart]));
        List = [List, dir(fullfile(BidsFolder, '**', ['*sub-', OldNamePart, '_*']))];
    else
        List = dir(fullfile(BidsFolder, '**', ['*sub-*', OldNamePart, '*']));
    end
    % For cases where the pattern could be found in the session, remove recordings, which were already renamed.
    List(contains({List.name}, '.ds')) = [];
    % Remove files
    List(~[List.isdir]) = [];
    for f = numel(List):-1:1
        if List(f).isdir
            % Check if new subject folder exists, then we need to move contents instead.
            NewFolder = fullfile(List(f).folder, regexprep(List(f).name, OldExpr(1:end-4), NewExpr(1:end-4))); % don't include _ses for folders
            CurrentFolder = fullfile(List(f).folder, List(f).name);
            if exist(NewFolder, 'dir')
                if Verbose
                    fprintf('Moving contents of %s to %s.\n', CurrentFolder, NewFolder);
                end
                [IsOk, Message] = movefile(fullfile(CurrentFolder, '*'), NewFolder);
                if ~IsOk
                    error(Message);
                end
                [IsOk, Message] = rmdir(fullfile(List(f).folder, List(f).name));
            else
                [IsOk, Message] = movefile(fullfile(List(f).folder, List(f).name), NewFolder); 
            end
            if ~IsOk
                error(Message);
            end
        end
    end
    
    % Rename metadata inside BIDS scans.tsv files.
    if isFull
        List = dir(fullfile(BidsFolder, '**', ['*sub-', NewNamePart, '_*_scans.tsv']));
    else
        List = dir(fullfile(BidsFolder, '**', ['*sub-*', NewNamePart, '*_scans.tsv']));
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

end