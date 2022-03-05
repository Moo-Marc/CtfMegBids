function BidsCopyManualInfo(BidsFolder, CopyFolder)
% Copy "manual" info (coregistration and artefact) from one BIDS dataset to another copy.
%
% If CopyFolder is missing or the same as BidsFolder, display the manual info
% only.
%
% Marc Lalancette 2022-03-05

% error('wip, coordinate system file part not implemented');

DisplayOnly = false;
if nargin < 2 || isempty(CopyFolder)
    DisplayOnly = true;
elseif strcmp(CopyFolder(end), filesep)
    CopyFolder(end) = '';
end
if isempty(BidsFolder) 
    error('Missing input arguments');
elseif ~DisplayOnly && strcmp(BidsFolder, CopyFolder)
    DisplayOnly = true;
end
if strcmp(BidsFolder(end), filesep)
    BidsFolder(end) = '';
end

% Allow processing subfolder of source, list before finding root BIDS folder.
DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
if ~exist(DataDescripFile, 'file')
    % Find CTF recordings (*.ds) in this folder.
    RecordingsList = dir(fullfile(BidsFolder, '**', '*_meg.json'));
    % Find all mri jsons.
    AnatList = dir(fullfile(BidsFolder, '**', '*_T1w.json'));
else
    % BIDS root: look only in subject folders (not sourcedata, etc.)
    RecordingsList = dir(fullfile(BidsFolder, 'sub-*', '**', '*_meg.json'));
    AnatList = dir(fullfile(BidsFolder, 'sub-*', '**', '*_T1w.json'));
end

% Find root BIDS folder.
while ~exist(DataDescripFile, 'file')
    if isempty(BidsFolder) || strcmp(BidsFolder, filesep)
        error('BIDS root folder not found: missing dataset_description.json');
    end
    % Go up to parent directory.
    BidsFolder = fileparts(BidsFolder);
    DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
end
if ~DisplayOnly
    % Verify destination is root BIDS folder.
    if ~exist(fullfile(CopyFolder, 'dataset_description.json'), 'file')
        error('Destination should be BIDS root, dataset_description.json not found.');
    end
end

% Process MRI
Fields = {'AnatomicalLandmarkCoordinates'};
iF = 1;
for iA = 1:numel(AnatList)
    fprintf('%s  ', AnatList(iA).name)
    JsonFile = fullfile(AnatList(iA).folder, AnatList(iA).name);
    if DisplayOnly
        J = bst_jsondecode(JsonFile, false);
        if isfield(J, Fields{iF})
            fprintf('%s = %s \n', Fields{iF}, num2str(J.(Fields{iF})));
        else
            fprintf('\n');
        end
    else
        % Find matching file or warn.
        CopyJsonFile = replace(JsonFile, BidsFolder, CopyFolder);
        if exist(CopyJsonFile, 'file')
            J = bst_jsondecode(JsonFile, false);
            CopyJ = bst_jsondecode(CopyJsonFile, false);
            if isfield(J, Fields{iF}) && (~isfield(CopyJ, Fields{iF}) || ...
                    ~isequal(CopyJ.(Fields{iF}), J.(Fields{iF})))
                CopyJ.(Fields{iF}) = J.(Fields{iF});
                WriteJson(CopyJ, CopyJsonFile);
                fprintf('copied.\n')
            else
                fprintf('no change.\n')
            end
        else
            fprintf('<strong>missing in destination!</strong>\n');
        end
    end
end

% Process MEG
Fields = {'SubjectArtefactDescription', 'IntendedFor'};
nF = numel(Fields);
for iR = 1:numel(RecordingsList)
    fprintf('%s: ', RecordingsList(iR).name);
    JsonFile = fullfile(RecordingsList(iR).folder, RecordingsList(iR).name);
    if DisplayOnly
        J = bst_jsondecode(JsonFile, false);
        for iF = 1:nF
            if isfield(J, Fields{iF})
                fprintf('%s = %s, ', Fields{iF}, num2str(J.(Fields{iF})));
            end
        end
        fprintf('\n');
    else
        % Find matching file or warn.
        CopyJsonFile = replace(JsonFile, BidsFolder, CopyFolder);
        if exist(CopyJsonFile, 'file')
            isSave = false;
            J = bst_jsondecode(JsonFile, false);
            CopyJ = bst_jsondecode(CopyJsonFile, false);
            for iF = 1:nF
                if isfield(J, Fields{iF}) && (~isfield(CopyJ, Fields{iF}) || ...
                        ~isequal(CopyJ.(Fields{iF}), J.(Fields{iF})))
                    CopyJ.(Fields{iF}) = J.(Fields{iF});
                    isSave = true;
                end
            end
            if isSave
                WriteJson(CopyJ, CopyJsonFile);
                fprintf('copied.\n')
            else
                fprintf('no change.\n')
            end
        else
            fprintf('<strong>missing in destination!</strong>\n');
        end
    end
end

%% Coordinate system file
% Fields = {'AnatomicalLandmarkCoordinates', 'FiducialsDescription'};


end




