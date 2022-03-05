function BidsRenameSession(BidsSubjectFolder, OldNamePart, NewNamePart, isFull)
% Rename a session ID in a CTF BIDS subject folder (and matching in sub-datasets).
%
% This still misses file names inside json files (AssociatedEmptyRoom,
% DigitizedHeadPoints) and requires running BidsRebuildAllFiles after.
%
% Files, folders, in some data files. Also look for other potential
% sub-datasets: derivatives, sourcedata, extras, etc.
% Marc Lalancette 2022-02-07

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
    OldExpr = ['ses-([a-zA-Z0-9]*)', OldNamePart, '([a-zA-Z0-9]*)_'];
    NewExpr = ['ses-$1', NewNamePart, '$2_'];
end

% Verify if unique, and if new session exists.
if isFull
    List = dir(fullfile(BidsSubjectFolder, ['ses-', OldNamePart, '*'])); % last * to avoid listing contents
else
    List = dir(fullfile(BidsSubjectFolder, ['ses-*', OldNamePart, '*']));
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
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '_*.ds']));
else
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*.ds']));
end
for f = 1:numel(List)
    Bids_ctf_rename_ds(fullfile(List(f).folder, List(f).name), ...
        regexprep(List(f).name, OldExpr, NewExpr));
end

% Rename other files.
if isFull
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '_*']));
else
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*_*']));
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
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-', OldNamePart, '*']));
else
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', OldNamePart, '*']));
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
    List = dir(fullfile(BidsSubjectFolder, '**', ['*ses-*', NewNamePart, '*_scans.tsv']));
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

