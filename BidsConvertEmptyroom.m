function BidsConvertEmptyroom(BidsFolder, Move, Revert, ForceSearch)
% Change the convention used for empty room noise recordings in a MEG BIDS dataset.
%
% Convention explicitly mentioned in BIDS standard: noise recordings are under a
% sub-emptyroom subject, with sessions named as dates (yyyymmdd).
% Alternate convention (also BIDS compliant): each noise recording is saved with the
% other recordings under the subject folder.
%
% This script by default goes from the sub-emptyroom convention to the
% within-subject convention. If Revert is true, goes the other way (not yet
% implemented).
%
% By default, noise recordings are copied from emptyroom to subject folders,
% since they can be shared between subjects.  If Move is true, they will instead
% be moved (and not found if other subjects shared them).
%
% BidsFolder must be a subfolder (e.g. subject folder) or the root folder of a
% BIDS dataset. Only recordings under the provided folder are converted.
%
% To search for "better" noise recording even if the existing association is ok,
% set ForceSearch to true.
%
% Marc Lalancette, 2022-02-08

if nargin < 4 || isempty(ForceSearch)
    ForceSearch = false;
end
if nargin < 3 || isempty(Revert)
    Revert = false;
elseif Revert
    error('Revert not yet implemented');
end
if nargin < 2 || isempty(Move)
    Move = false;
end
if nargin < 1 || isempty(BidsFolder)
    error('BidsFolder input required.');
elseif ~isfolder(BidsFolder)
    error('BidsFolder not found.');
end

% Get all recordings metadata.
[Recordings, ~, BidsFolder] = BidsRecordings(BidsFolder, false, true); % not Verbose, NoiseFirst
nR = numel(Recordings);

EmptyroomRecordings = [];
AllFound = true;
for r = 1:nR
    Recording = fullfile(BidsFolder, Recordings(r).Folder, Recordings(r).Name);
    % If noise field exist, check if file exists, if not locate.
    if ~Move
        % For efficiency, reuse list of emptyroom recordings.
        [Noise, Found, EmptyroomRecordings] = BidsFindAssociatedNoise(...
            Recording, Recordings(r), [], [], [], EmptyroomRecordings, ForceSearch);
    else
        [Noise, Found] = BidsFindAssociatedNoise(Recording, Recordings(r), [],[],[],[], ForceSearch);
    end
    if ~Found && ~Recordings(r).isNoise
        % Already warned.
        AllFound = false;
        continue;
    elseif Recordings(r).isNoise
        % For now skipping.
        continue;
    end
    % Check if already in subject folder, compare relative paths.
    [NoisePath, NoiseName, NoiseExt] = fileparts(Noise);
    NoiseName = [NoiseName, NoiseExt];
    if strcmp(Recordings(r).Folder, NoisePath)
        if Found == 1 % and not greater, so new
            Recordings(r).Meg.AssociatedEmptyRoom = Noise;
            WriteJson(Recordings(r).Files.Meg, Recordings(r).Meg);
        end
    else
        % Double check it's from emptyroom subject
        [~, NoiseInfo] = BidsParseRecordingName(NoiseName);
        if ~strcmp(NoiseInfo.Subject, 'emptyroom')
            error('Unexpected location for noise recording %s associated with %s.', ...
                Noise, fullfile(Recordings(r).Folder, Recordings(r).Name));
        end
        [~, BidsInfo] = BidsParseRecordingName(Recordings(r).Name);
        NoiseInfo.Subject = BidsInfo.Subject;
        NoiseInfo.Session = BidsInfo.Session;
        NewName = BidsBuildRecordingName(NoiseInfo);
        % Check if was already copied (but association not updated).
        if ~exist(fullfile(BidsFolder, Recordings(r).Folder, NewName), 'dir')
            if Move
                % Move recording
                Bids_ctf_rename_ds(fullfile(BidsFolder, Noise), NewName, fullfile(BidsFolder, Recordings(r).Folder));
            else
                % Copy first, then rename.
                % This creates the new dataset folder correctly, without renaming.
                [isOk, Message] = copyfile(fullfile(BidsFolder, Noise), ...
                    fullfile(BidsFolder, Recordings(r).Folder, NoiseName));
                if ~isOk
                    error(Message);
                end
                Bids_ctf_rename_ds(fullfile(BidsFolder, Recordings(r).Folder, NoiseName), NewName);
            end
        end
        % Copy sidecar files 
        % Exclude _coordsys.json which is common to all runs and should contain
        % digitized info and possibly EEG from non-noise runs.
        OrigName = NoiseName(1:end-6); % remove 'meg.ds'
        Files = dir(fullfile(BidsFolder, NoisePath, [OrigName, '*']));
        for iFile = 1:length(Files)
            NewFile = fullfile(BidsFolder, Recordings(r).Folder, strrep(Files(iFile).name, OrigName, NewName(1:end-6))); % exclude 'meg.ds'
            if ~exist(NewFile, 'file')
                if Move
                    [isOk, Message] = movefile(fullfile(BidsFolder, NoisePath, Files(iFile).name), NewFile);
                else %if ~exist(NewFile, 'dir') % what was this about? no folders here...
                    [isOk, Message] = copyfile(fullfile(BidsFolder, NoisePath, Files(iFile).name), NewFile);
                end
                if ~isOk
                    error(Message);
                end
            end
        end
        % Edit destination session table (ignore emptyroom session table).
        BidsBuildSessionFiles(fullfile(BidsFolder, Recordings(r).Folder, NewName), [], true, true); % Overwrite, SaveFiles.
        % Update 
        Recordings(r).Meg.AssociatedEmptyRoom = Noise;
        WriteJson(Recordings(r).Files.Meg, Recordings(r).Meg);
    end
end

% Delete empty sessions under emptyroom
if Move
    SessionList = dir(fullfile(BidsFolder, 'sub-emptyroom'));
    if ~isempty(SessionList)
        for iSes = 1:numel(SessionList)
            RecordingsList = dir(fullfile(SessionList(iSes).folder, '**', '*.ds'));
            if isempty(RecordingsList)
                [isOk, Message] = rmdir(SessionList(iSes).folder, 's');
                if ~isOk
                    error(Message);
                end
            end
        end
        SessionList = dir(fullfile(BidsFolder, 'sub-emptyroom'));
    end
    if isempty(SessionList)
        [isOk, Message] = rmdir(fullfile(BidsFolder, 'sub-emptyroom'));
        if ~isOk
            error(Message);
        end
    else
        warning('Sessions remain under sub-emptyroom.');
    end
end

if ~AllFound
    warning('Some sessions not associated with a noise recording (none found matching).');
end

end

