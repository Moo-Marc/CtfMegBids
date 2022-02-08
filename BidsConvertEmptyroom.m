function BidsConvertEmptyroom(BidsFolder, Revert)
% Change the convention used for empty room noise recordings in a MEG BIDS dataset.
%
% Convention explicitly mentioned in BIDS standard: noise recordings are under a
% sub-emptyroom subject, with sessions named as dates (yyyymmdd).
% Alternate convention (also BIDS compliant): each noise recording is saved with the
% other recordings under the subject folder.
%
% This script by default goes from the sub-emptyroom convention to the within-subject convention.
% If Revert is true, goes the other way (not yet implemented).
%
% Marc Lalancette, 2022-01-09

if nargin < 2 || isempty(Revert)
    Revert = false;
elseif Revert
    error('Revert not yet implemented');
end
if nargin < 1 || isempty(BidsFolder)
    error('BidsFolder input required.');
elseif ~isfolder(BidsFolder)
    error('BidsFolder not found.');
end

% Get all recordings metadata.
Recordings = BidsRecordings(BidsFolder, false, true); % not Verbose, NoiseFirst
nR = numel(Recordings);

AllFound = true;
for r = 1:nR
    Recording = fullfile(BidsFolder, Recordings(r).Folder, Recordings(r).Name);
    % If noise field exist, check if file exists, if not locate.
    [Noise, Found] = BidsFindAssociatedNoise(Recording, Recordings(r));
    if ~Found && ~Recordings(r).isNoise
        % Already warned.
        AllFound = false;
        continue;
    end
    % Check if already in subject folder, compare relative paths.
    [NoisePath, NoiseName, NoiseExt] = fileparts(Noise);
    if strcmp(Recordings(r).Folder, NoisePath)
        if Found == 1 % and not greater, so new
            SaveAssociation();
        end
    else
        % Double check it's from emptyroom subject
        [~, BidsInfo] = BidsParseRecordingName(Recordings(r).Name);
        if ~strcmp(BidsInfo.Subject, 'emptyroom')
            error('Unexpected location for noise recording %s associated with %s.', ...
                Noise, fullfile(Recordings(r).Folder, Recordings(r).Name));
        end
        % Move recording
        Bids_ctf_rename_ds(fullfile(BidsFolder, Noise), Recording, []);
        % Move sidecar files
        OrigName = NoiseName(1:end-3); % remove 'meg' 
        [~, NoiseInfo] = BidsParseRecordingName([NoiseName, NoiseExt]);
        NoiseInfo.Subject = BidsInfo.Subject;
        NoiseInfo.Session = BidsInfo.Session;
        NewName = BidsBuildRecordingName(NoiseInfo);
        NewName(end-5:end) = []; % remove 'meg.ds'
        Files = dir(fullfile(BidsFolder, NoisePath, [OrigName, '*']));
        for iFile = 1:length(Files)
            movefile(fullfile(BidsFolder, NoisePath, Files(iFile).name), ...
                fullfile(BidsFolder, Recordings(r).Folder, strrep(Files(iFile).name, OrigName, NewName)));
        end
        % Edit destination session table (ignore emptyroom session table).
        BidsBuildSessionFiles(Recording);
        
        SaveAssociation();
    end
end

% Delete empty sessions under emptyroom
SessionList = dir(fullfile(BidsFolder, 'sub-emptyroom'));
if ~isempty(SessionList)
    for iSes = 1:numel(SessionList)
        RecordingsList = dir(fullfile(SessionList(iSes).folder, '**', '*.ds'));
        if isempty(RecordingsList)
            [Status, Message] = rmdir(SessionList(iSes).folder, 's');
            if ~Status
                error(Message);
            end
        end
    end
    SessionList = dir(fullfile(BidsFolder, 'sub-emptyroom'));
end
if isempty(SessionList)
    [Status, Message] = rmdir(fullfile(BidsFolder, 'sub-emptyroom'));
    if ~Status
        error(Message);
    end
else
    warning('Sessions remain under sub-emptyroom.');
end
if ~AllFound
    warning('Some sessions not associated with a noise recording (none found matching).');
end

    function SaveAssociation()
        MegJsonFile = fullfile(BidsFolder, Recordings(r).Folder, [Recordings(r).Name(1:end-3), '.json']);
        % Save the struct to a json file.
        WriteJson(MegJsonFile, Recordings(r).Meg);
    end
end

