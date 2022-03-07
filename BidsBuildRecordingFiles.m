function BidsInfo = BidsBuildRecordingFiles(Recording, BidsInfo, Overwrite, SaveFiles, RemoveEmptyFields, iLog)
% Create BIDS metadata files for a single CTF MEG recording.
% Satisfies BIDS version indicated in BidsBuildStudyFiles.
%
% Required BidsInfo fields: Subject, Session, Task
% Optional BidsInfo fields: Noise (equivalent to BidsInfo.Meg.AssociatedEmptyRoom),
%   Artefact (equivalent to BidsInfo.Meg.SubjectArtefactDescription),
%   but these 2 "simplified" fields get removed in BidsInfo output.
% All other fields (as returned by BidsRecordings) are optional and will have precedence.
%
% Overwrite [default false]: if true existing metadata files are replaced.  Does not
% apply at the level of individual metadata fields: these are extracted from the raw
% data files except for existing fields provided in BidsInfo which have precedence.
% This is done at the first field level of each json file (not sub-fields), or at
% once for the full content of tsv tables (coordsys or events). So care must be taken
% or the new files could be missing fields and possibly be non-compliant.
%
% iLog: File ID of log file already open for writing, or output to Matlab command
% window (iLog=1, default).
%
% Authors: Elizabeth Bock, Marc Lalancette, 2017 - 2022-02-08
    
    if nargin < 6 || isempty(iLog)
        iLog = 1;
    end
    if nargin < 5 || isempty(RemoveEmptyFields)
        RemoveEmptyFields = false;
    end    
    if nargin < 4 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 3 || isempty(Overwrite)
        Overwrite = false;
    end
    if nargout
        Output = true;
    else
        Output = false;
    end
    if ~SaveFiles && ~Output
        % Nothing to do.
        warning('Selected options leave nothing to do.');
        return;
    end
    
    % Dependencies
    BidsSetPath;
    
    if any(~isfield(BidsInfo, {'Subject', 'Session', 'Task'}))
        error('Missing required field in BidsInfo: Subject, Session, Task.');
    end
    
    [RecPath, RecName, RecExt] = fileparts(Recording);
    isNoise = contains(RecName, 'emptyroom') || strcmpi(BidsInfo.Task, 'noise');
    if isfield(BidsInfo, 'isNoise') && xor(isNoise, BidsInfo.isNoise)
        fprintf(iLog, '  Warning: Conflicting info whether this is a noise recording, ignoring BidsInfo.isNoise: %s\n', RecName);
    end 

    % Collect required metadata from recording files.
    
    Res4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']);
    Res4 = Bids_ctf_read_res4(Res4File);
    
    InfoDsFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.infods']);
    if ~exist(InfoDsFile, 'file')
        fprintf(iLog, '  Missing InfoDs file, and therefore some metadata, for recording %s\n', RecName);
        InfoDs = [];
    else
        InfoDs = CPersistToStruct(readCPersist(InfoDsFile, 0));
    end
    
    BadChannelsFile = fullfile(RecPath, [RecName, RecExt], 'BadChannels');
    % Recreate if missing (e.g. ds transferred via OneDrive).
    if ~exist(BadChannelsFile, 'file')
        Fid = fopen(BadChannelsFile, 'w');
        fclose(Fid);
        BadChannels = {};
    else        
        Fid = fopen(BadChannelsFile);
        BadChannels = textscan(Fid, '%s');
        BadChannels = BadChannels{1};
    end
    
    AcqFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.acq']);
    Acq = CPersistToStruct(readCPersist(AcqFile, 0));
    AcqFields = fieldnames(Acq)';
    for Field = AcqFields(contains(AcqFields, 'dacSetups'))
        Field = Field{1}; %#ok<*FXSET>
        if ~exist('Dac', 'var')
            Dac = Acq.(Field);
        else
            Dac(end+1) = Acq.(Field); %#ok<*AGROW>
        end
    end
    HeadCoilFreq = [Dac([Dac.enabled] & strncmp({Dac.hardwareName}, 'HDAC', 4)).frequency];
    % Is this a "continuous" recording, including if recorded in trials?
    if Res4.gSetUp.no_trials <= 1
        Continuous = true;
    elseif Acq.offset_mode == 1 % 1 means offset removal per trial.
        % Not clear if this fits the BIDS definition of epoched, but since
        % the data can't simply be stitched back together, let's not mark
        % it as continuous.
        Continuous = false;
    else
        % Look for any triggers defined as trial start (sync enabled).
        for Field = AcqFields(contains(AcqFields, 'triggerSetups'))
            Field = Field{1};
            if ~exist('AnalogTrigger', 'var')
                AnalogTrigger = Acq.(Field);
            else
                AnalogTrigger(end+1) = Acq.(Field);
            end
        end
        for Field = AcqFields(contains(AcqFields, 'triggerPatterns'))
            Field = Field{1};
            if ~exist('DigitalTrigger', 'var')
                DigitalTrigger = Acq.(Field);
            else
                DigitalTrigger(end+1) = Acq.(Field);
            end
        end
        if ( exist('AnalogTrigger', 'var') && any([AnalogTrigger.enabled] & [AnalogTrigger.synchEnabled]) ) || ...
                ( exist('DigitalTrigger', 'var') && any([DigitalTrigger.sync]) )
            Continuous = false;
        else
            Continuous = true;
        end
    end
    % The line frequency is always present in this .acq file field, but
    % most likely the default if disabled.
    if isfield(Acq, 'powerlineDetector') && Acq.powerlineDetector.enabled % Field missing in some DsqSetup datasets.
        PowerLineFreq = Acq.powerlineDetector.frequency;
    else
        PowerLineFreq = 60;
    end
    
    % There can be a head points pos file + an eeg pos file.  Use the
    % former which should also have the coils and anatomical fiducial points.
    PosFile = dir(fullfile(RecPath, '*.pos'));
    nHeadPoints = 0;
    iAnatomical = [];
    iHeadCoils = [];
    % We seem to update the Res4 file with EEG channel positions. So don't
    % require EEG positions in a pos file.
    %     EEGLoc = false;
    for iPos = 1:numel(PosFile)
        Pos = in_channel_pos(fullfile(PosFile(iPos).folder, PosFile(iPos).name));
        if nHeadPoints <= 1 && isfield(Pos, 'HeadPoints') % && isfield(Pos.HeadPoints, 'Label')
            iAnatomical = find(strcmp(Pos.HeadPoints.Type, 'CARDINAL'));
            iHeadCoils = find(strcmp(Pos.HeadPoints.Type, 'HPI'));
            nHeadPoints = sum(strcmp(Pos.HeadPoints.Type, 'EXTRA'));
            if nHeadPoints > 1
                break;
            end
        end
        %         if isfield(Pos, 'Channel') && ~isempty(Pos.Channel) && ...
        %                 ~isempty([Pos.Channel(contains({Pos.Channel.Type}, 'EEG')).Loc])
        %             EEGLoc = true;
        %         end
    end
    
    % Find associated noise recording in BIDS dataset.
    Noise = BidsFindAssociatedNoise(Recording, BidsInfo, iLog);
    if isfield(BidsInfo, 'Noise') && Output
        BidsInfo = rmfield(BidsInfo, 'Noise');
    end

    % Log notes about recording quality
    if isfield(BidsInfo, 'Artefact') 
        Artefact = char(BidsInfo.Artefact); % Convert [] to ''.
        if Output
            BidsInfo = rmfield(BidsInfo, 'Artefact');
        end
    elseif isfield(BidsInfo, 'Meg') && isfield(BidsInfo.Meg, 'SubjectArtefactDescription')
        % Check if it was read from a BIDS .json.
        Artefact = BidsInfo.Meg.SubjectArtefactDescription;
    else
        Artefact = '';
    end
    
    % Find associated structural MRI.
    iRelativePath = strfind(RecPath, [filesep, 'sub-']);
    BidsFolder = RecPath(1:iRelativePath(1)-1);
    NiiFile = dir(fullfile(BidsFolder, ['sub-', BidsInfo.Subject], ['_ses-', BidsInfo.Session], 'anat', '*.nii*'));
    
    
    % ------------------------------------------------------------
    % Recording sidecar file
    MegJsonFile = fullfile(RecPath, [RecName, '.json']);
    if ~exist(MegJsonFile, 'file') || Overwrite || Output
        
        J = struct();
        
        % Generic fields
        % Required
        J.TaskName = BidsInfo.Task; % Must match filename task label. Resting state must start with 'rest'.
        % Should be present
        J.InstitutionName = 'McConnell Brain Imaging Center, Montreal Neurological Institute-Hospital, McGill University';
        J.InstitutionAddress = '3801 University St., Montreal, QC, Canada';
        J.Manufacturer = 'CTF';
        J.ManufacturersModelName = 'CTF-275';
        if ~isempty(InfoDs)
            J.SoftwareVersions = InfoDs.DATASET_INFO.DATASET_COLLECTIONSOFTWARE;
        end
        if isNoise
            J.TaskDescription = 'Empty-room (no subject) noise recording.';
            %J.Instructions = 'n/a';
            %J.CogAtlasID = ''; % Validator complains if empty.
            %J.CogPOID = '';
        end
        if strncmpi(J.TaskName, 'rest', 4)
            J.TaskDescription = 'Rest eyes open';
            J.CogAtlasID = 'http://www.cognitiveatlas.org/task/id/trm_4c8a834779883';
            J.CogPOID = 'http://wiki.cogpo.org/index.php?title=Rest'; % Nothing on that page though...
        end
        %     J.DeviceSerialNumber = [];
        
        % MEG specific fields
        % Required
        J.SamplingFrequency = Res4.gSetUp.sample_rate;
        J.PowerLineFrequency = PowerLineFreq; % Possibly extracted from .acq file above.
        J.DewarPosition = 'upright';
        % Possibly no MEG channels.
        iMeg = find(ismember([Res4.SensorRes.sensorTypeIndex], 4:7), 1);
        if ~isempty(iMeg)
            J.SoftwareFilters.SpatialCompensation.GradientOrder = ...
                Res4.SensorRes(iMeg).grad_order_no; % or Acq.gradient_order
        end
        for f = 1:numel(Res4.filter)
            J.SoftwareFilters.TemporalFilter(f).Type = Res4.filter(f).fType;
            J.SoftwareFilters.TemporalFilter(f).Class = Res4.filter(f).fClass;
            J.SoftwareFilters.TemporalFilter(f).Frequency = Res4.filter(f).freq;
            J.SoftwareFilters.TemporalFilter(f).Parameters = Res4.filter(f).params;
        end
        DigitizedHeadPoints = ~isNoise && ~isempty(PosFile) && nHeadPoints > 1;
        J.DigitizedHeadPoints = DigitizedHeadPoints;
        % "Whether anatomical landmark points (fiducials) are contained within this recording."
        % I interpret that to include head coils.
        DigitizedLandmarks = ~isNoise && (~isempty(iAnatomical) || ~isempty(iHeadCoils)); % ~isempty(PosFile) &&
        J.DigitizedLandmarks = DigitizedLandmarks;
        % Should be present
        J.MEGChannelCount = sum(ismember([Res4.SensorRes.sensorTypeIndex], 4:7));
        J.MEGREFChannelCount = sum(ismember([Res4.SensorRes.sensorTypeIndex], 0:3));
        isEEG = [Res4.SensorRes.sensorTypeIndex] == 9;
        EEGChannelCount = sum(isEEG);
        J.ECOGChannelCount = 0;
        J.SEEGChannelCount = 0;
        % Subtract other types from EEG count, though they should be different index type.
        isEOG = contains(Res4.channel_names, 'EOG');
        J.EOGChannelCount = sum(isEOG);
        isECG = contains(Res4.channel_names, 'ECG');
        J.ECGChannelCount = sum(isECG);
        isEMG = contains(Res4.channel_names, 'EMG');
        J.EMGChannelCount = sum(isEMG);
        EEGChannelCount = EEGChannelCount - sum(isEEG & (isEMG | isECG | isEOG));
        J.EEGChannelCount = EEGChannelCount;
        if J.EOGChannelCount + J.ECGChannelCount < 3 && ...
                sum([Res4.SensorRes.sensorTypeIndex] == 21) - J.EMGChannelCount == 3
            % Channels probably not renamed but present.
            J.EOGChannelCount = 2;
            J.ECGChannelCount = 1;
        end
        J.MiscChannelCount = sum([Res4.SensorRes.sensorTypeIndex] == 18); % "miscellaneous analog channels for auxiliary signals"
        J.TriggerChannelCount = sum(ismember([Res4.SensorRes.sensorTypeIndex], [11,19,20])); % "channels for digital (TTL bit level) triggers"
        J.RecordingDuration = NumTrim((Res4.gSetUp.no_samples * Res4.gSetUp.no_trials) / Res4.gSetUp.sample_rate, 6); % in seconds, round to micro-s
        if Continuous % Extracted from .acq file above.
            J.RecordingType = 'continuous';
            %J.EpochLength = 'n/a'; % Must be a number.
        else
            J.RecordingType = 'epoched';
            J.EpochLength = NumTrim(Res4.gSetUp.no_samples / Res4.gSetUp.sample_rate, 6); % in seconds, round to micro-s
        end
        if ~isempty(InfoDs)
            J.ContinuousHeadLocalization = InfoDs.DATASET_INFO.DATASET_HZ_MODE == 5;
        end
        if J.ContinuousHeadLocalization
            J.HeadCoilFrequency = HeadCoilFreq; % Extracted from .acq file above.
            % Don't read head motion if nominal position used. (TO VERIFY, could still be good)
            if ~isempty(InfoDs) && ~InfoDs.DATASET_INFO.DATASET_NOMINALHCPOSITIONS
                %         J.MaxMovement = [];
                %     else
                J.MaxMovement = NumTrim(1000 * InfoDs.DATASET_INFO.DATASET_MAXHEADMOTION, 3); % m to mm, round to micro-m
            end
        end
        if ~isempty(Artefact)
            J.SubjectArtefactDescription = Artefact;
        elseif ~isNoise % Don't include this field empty for noise recording.
            J.SubjectArtefactDescription = '';
        end
        if ~isNoise && ~isempty(Noise)
            J.AssociatedEmptyRoom = Noise;
        end
        J.HardwareFilters.Antialiasing.Type = 'Low pass';
        J.HardwareFilters.Antialiasing.Class = 'Elliptic';
        J.HardwareFilters.Antialiasing.Order = 8;
        J.HardwareFilters.Antialiasing.Frequency = J.SamplingFrequency /4; 
        J.HardwareFilters.Antialiasing.PassBandRippleDb = 0.1;
        J.HardwareFilters.Antialiasing.NyquistAttenuationDb = 120;
        % Optional, if simultaneous EEG
        %     J.EEGPlacementScheme = [];
        %     J.ManufacturersAmplifierModelName = [];
        %     J.CapManufacturer = [];
        %     J.CapManufacturersModelName = [];
        %     J.EEGReference = [];
        
        if isfield(BidsInfo, 'Meg')
            J = StructOverwrite(J, BidsInfo.Meg);
        end
        if RemoveEmptyFields
            J = StructTrim(J);
        end
        if SaveFiles
            % Save the struct to a json file.
            WriteJson(MegJsonFile, J);
        end
        if Output
            BidsInfo.Meg = J;
            BidsInfo.Files.Meg = MegJsonFile;
        end
    end % if meg json file exists
    
    
    % ------------------------------------------------------------
    % Coordinate system sidecar file
    
    % More restrictive naming for this file: one for multiple tasks/runs.
    % sub-<label>[_ses-<label>][_acq-<label>]_coordsystem.json
    CoordFile = fullfile(RecPath, ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_coordsystem.json']);
    
    %     % Don't create the coord file for noise that's with real data.
    %     isNoiseCoord = isNoise && ~contains(RecName, 'emptyroom');

    % What can change between (regular) runs is the presence of EEG channels.
    % Don't create the coord file for noise: no head, not CTF coord sys.
    if ~isNoise
        % This is technically wrong, we could load the meg.json to check, but if
        % CoordFile already exists, assume it's ok.  The risk of missing the
        % EEGCoordinateSystem info is low anyway.
        if ~exist('EEGChannelCount', 'var')
            EEGChannelCount = 0;
        end
        if ~exist(CoordFile, 'file') || Overwrite || Output || EEGChannelCount > 0
            J = struct();
            System = 'CTF';
            Units = 'cm';
            MegDescription = 'Based on the initial MEG localization of the head coils for each recording. The origin is exactly between the left ear head coil (coilL near LPA) and the right ear head coil (coilR near RPA); the X-axis goes towards the nasion head coil (coilN near NAS); the Y-axis goes approximately towards coilL, orthogonal to X and in the plane spanned by the 3 head coils; the Z-axis goes approximately towards the vertex, orthogonal to X and Y';
            DigDescription = 'Based on the digitized locations of the head coils. The origin is exactly between the left ear head coil (coilL near LPA) and the right ear head coil (coilR near RPA); the X-axis goes towards the nasion head coil (coilN near NAS); the Y-axis goes approximately towards coilL, orthogonal to X and in the plane spanned by the 3 head coils; the Z-axis goes approximately towards the vertex, orthogonal to X and Y';

            % MEG sensor coordinates are in the res4 file. Available both in CTF
            % head coordinates and dewar coordinates.
            J.MEGCoordinateSystem = System;
            J.MEGCoordinateUnits = Units;
            J.MEGCoordinateSystemDescription = MegDescription;
            % EEG electrode locations are only available if they were digitized.
            if EEGChannelCount > 0
                J.EEGCoordinateSystem = System;
                J.EEGCoordinateUnits = Units;
                J.EEGCoordinateSystemDescription = DigDescription;
            end
            if DigitizedHeadPoints
                J.DigitizedHeadPoints = PosFile(iPos).name; % bug in BIDS 1.7.0 indicates this is boolean (again).
                J.DigitizedHeadPointsCoordinateSystem = System;
                J.DigitizedHeadPointsCoordinateUnits = Units;
                J.DigitizedHeadPointsCoordinateSystemDescription = DigDescription;
            end
            % Head coil coordinates are available both in the digitized file and
            % MEG recordings. Here we display the digitized ones since the
            % latter varies per recording.
            if DigitizedLandmarks
                % We say the coordinates are in cm, so convert them to cm.
                % Round to micro-m
                if ~isempty(iHeadCoils)
                    J.AnatomicalLandmarkCoordinates = struct( ...
                        'NAS', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'Nasion')), 2)', 4), ...
                        'LPA', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'LPA')), 2)', 4), ...
                        'RPA', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'RPA')), 2)', 4) );
                    J.AnatomicalLandmarkCoordinateSystem = System;
                    J.AnatomicalLandmarkCoordinateUnits = Units;
                    J.AnatomicalLandmarkCoordinateSystemDescription = DigDescription;
                    J.HeadCoilCoordinates = struct( ...
                        'coilN', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'HPI-N')), 2)', 4), ...
                        'coilL', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'HPI-L')), 2)', 4), ...
                        'coilR', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'HPI-R')), 2)', 4) );
                    J.HeadCoilCoordinateSystem = System;
                    J.HeadCoilCoordinateUnits = Units;
                    J.HeadCoilCoordinateSystemDescription = DigDescription;
                    % Don't assume head coil positioning if more than a few EEG channels.
                    if EEGChannelCount > 10
                        J.FiducialsDescription = 'The anatomical landmarks are the nasion and the left and right junctions between the tragus and the helix.  The head coils, usually placed above the nasion on the forehead (coilN) and near the pre-auricular points (coilL and coilR), may have been placed differently because of EEG.';
                    else
                        J.FiducialsDescription = 'The anatomical landmarks are the nasion and the left and right junctions between the tragus and the helix.  The head coils are placed above the nasion on the forehead (coilN) and near the pre-auricular points (coilL and coilR).';
                    end
                else %if isempty(iHeadCoils) && ~isempty(iAnatomical)
                    % Assume that if only one set of markers were digitized, they are
                    % the head coils.
                    J.HeadCoilCoordinates = struct( ...
                        'coilN', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'Nasion')), 2)', 4), ...
                        'coilL', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'LPA')), 2)', 4), ...
                        'coilR', NumTrim(100 * mean(Pos.HeadPoints.Loc(:, strcmp(Pos.HeadPoints.Label, 'RPA')), 2)', 4) );
                    J.HeadCoilCoordinateSystem = System;
                    J.HeadCoilCoordinateUnits = Units;
                    J.HeadCoilCoordinateSystemDescription = DigDescription;
                    if EEGChannelCount > 10
                        J.FiducialsDescription = 'The head coils, usually placed above the nasion on the forehead (coilN) and near the pre-auricular points (coilL and coilR), may have been placed differently because of EEG.';
                    else
                        J.FiducialsDescription = 'The head coils are placed above the nasion on the forehead (coilN) and near the pre-auricular points (coilL and coilR).';
                    end
                end
            end

            if ~isempty(NiiFile)
                J.IntendedFor = fullfile(['_ses-', BidsInfo.Session], 'anat', NiiFile(1).name); % Path or list of path relative to the subject subfolder pointing to the structural MRI.
                %         JT1wMRI.AnatomicalLandmarkCoordinates = ; % voxel coordinates of the actual anatomical landmarks for co-registration of MEG with structural MRI.
                if ispc()
                    J.IntendedFor = strrep(J.IntendedFor, '\', '/');
                end
            end

            if isfield(BidsInfo, 'CoordSystem')
                J = StructOverwrite(J, BidsInfo.CoordSystem);
            end
            if RemoveEmptyFields
                J = StructTrim(J);
            end
            if SaveFiles
                % Save the struct to a json file.
                WriteJson(CoordFile, J);
            end
            if Output
                BidsInfo.CoordSystem = J;
                BidsInfo.Files.CoordSystem = CoordFile;
            end

        end % if coordinate file exists
    elseif Output
        % First level fields needed even if noise.
        BidsInfo.CoordSystem = struct();
        BidsInfo.Files.CoordSystem = '';
    end
    
    
    % ------------------------------------------------------------
    % Channel table file
    
    ChannelFile = fullfile(RecPath, [RecName(1:end-3), 'channels.tsv']);
    if ~isfield(BidsInfo, 'Channels') && ...
            (~exist(ChannelFile, 'file') || Overwrite || Output)
        
        nChan = numel(Res4.channel_names);
        
        clear J;
        J(nChan) = struct('name', '', 'type', '', 'units', '', 'description', '', 'sampling_frequency', '', ...
            'low_cutoff', '', 'high_cutoff', '', 'notch', '', 'software_filters', '', 'status', ''); % status_description
        
        for iChan = 1:nChan
            iType = Res4.SensorRes(iChan).sensorTypeIndex;
            if ismember(iType, [8, 9, 21]) % These should be bipolar, i.e. type 21, but not in practice.
                if contains(Res4.channel_names{iChan}, 'VEOG')
                    iType = 31;
                elseif contains(Res4.channel_names{iChan}, 'HEOG')
                    iType = 32;
                elseif contains(Res4.channel_names{iChan}, 'ECG')
                    iType = 33;
                elseif contains(Res4.channel_names{iChan}, 'EMG')
                    iType = 34;
                elseif contains(Res4.channel_names{iChan}, 'EOG')
                    iType = 35;
                end
            end
            
            Filt = '';
            if ismember(iType, 4:7)
                if isempty(Filt)
                    Filt = 'SpatialCompensation';
                else
                    Filt = [Filt, ', SpatialCompensation'];
                end
            end
            if ismember(iType, [0:10, 14, 18, 21, 22, 31:35]) % include ADC and DAC channels
                iLow = find(contains({Res4.filter.fType}, 'LOWPASS')); % { TYPERROR, LOWPASS, HIGHPASS, NOTCH } filtType;
                iHigh = find(contains({Res4.filter.fType}, 'HIGHPASS'));
                iNotch = find(contains({Res4.filter.fType}, 'NOTCH'));
                if ~isempty(iLow)
                    if isempty(Filt)
                        Filt = 'LowPass';
                    else
                        Filt = [Filt, ', LowPass'];
                    end
                    Low = [Res4.filter(iLow).freq];
                else
                    Low = [];
                end
                if ~isempty(InfoDs)
                    Low = num2str([Low, InfoDs.DATASET_INFO.DATASET_UPPERBANDWIDTH]); % num2str(Res4.gSetUp.sample_rate/4);
                else
                    Low = num2str([Low, Res4.gSetUp.sample_rate/4]); 
                end
                if ~isempty(iHigh)
                    if isempty(Filt)
                        Filt = 'HighPass';
                    else
                        Filt = [Filt, ', HighPass'];
                    end
                    High = num2str([Res4.filter(iHigh).freq]);
                    % num2str(InfoDs.DATASET_INFO.DATASET_LOWERBANDWIDTH);
                else
                    High = 'n/a';
                end
                if ~isempty(iNotch)
                    if isempty(Filt)
                        Filt = 'Notch';
                    else
                        Filt = [Filt, ', Notch'];
                    end
                    Notch = num2str([Res4.filter(iNotch).freq]);
                else
                    Notch = 'n/a';
                end
                if isempty(Filt)
                    Filt = 'n/a';
                end
            else
                Low = 'n/a';
                High = 'n/a';
                Notch = 'n/a';
                Filt = 'n/a';
            end
            
            % Use "short" channel names, without the system ID.
            % iType is 0-indexed, add 1.
            iType = iType + 1;
            %             fprintf(Fid, '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n', ...
            %                 strtok(Res4.channel_names{iChan}, '-'), Res4.SensorTypes{iType}, Res4.SensorUnit{iType}, Res4.SensorDesc{iType}, ...
            %                 num2str(Res4.gSetUp.sample_rate), Low, High, Notch, Filt, 'good');
            J(iChan).name = strtok(Res4.channel_names{iChan}, '-');
            J(iChan).type = Res4.SensorTypes{iType};
            J(iChan).units = Res4.SensorUnit{iType};
            J(iChan).description = Res4.SensorDesc{iType};
            J(iChan).sampling_frequency = Res4.gSetUp.sample_rate; % num2str(Res4.gSetUp.sample_rate);
            J(iChan).low_cutoff = Low;
            J(iChan).high_cutoff = High;
            J(iChan).notch = Notch;
            J(iChan).software_filters = Filt;
            if ismember(J(iChan).name, BadChannels)
                J(iChan).status = 'bad';
            else
                J(iChan).status = 'good';
            end
        end % channel loop
        
        J = struct2table(J);
        if SaveFiles
            writetable(J, ChannelFile, 'FileType', 'text', 'Delimiter', '\t');
        end
        if Output
            BidsInfo.Channels = J;
            BidsInfo.Files.Channels = ChannelFile;
        end
    end % if channel file exists
    
    
    % ------------------------------------------------------------
    % Events table file
    
    EventsFile = fullfile(RecPath, [RecName(1:end-3), 'events.tsv']);
    if ~isfield(BidsInfo, 'Events') && ...
            (~exist(EventsFile, 'file') || Overwrite || Output)
        
        Mrk = openmrk(Recording, false, true);
        % Convert struct to table.
        clear J;
        J = table('Size', [0, 5], 'VariableTypes', {'double', 'double', 'double', 'double', 'cellstr'});
        % BIDS requires a duration, but CTF doesn't provide that info, so we must put 0.
        for m = 1:numel(Mrk)
            if ~isempty(Mrk(m).Count) && Mrk(m).Count > 0
                MrkVal = {Mrk(m).Name};
                J = vertcat(J, table( (Res4.gSetUp.no_samples * (Mrk(m).Samples(:,1) - 1)) / Res4.gSetUp.sample_rate + Mrk(m).Samples(:,2), ...
                    zeros(Mrk(m).Count, 1), Mrk(m).Samples(:,1), ...
                    round(Mrk(m).Samples(:,2) * Res4.gSetUp.sample_rate), MrkVal(ones(Mrk(m).Count, 1)) ));
            end
        end
        % We have to name the variables after filling the table otherwise it won't let us concatenate.
        J.Properties.VariableNames = {'onset', 'duration', 'ds_trial', 'sample', 'value'};
        
        if SaveFiles && ~isempty(J)
            writetable(J, EventsFile, 'FileType', 'text', 'Delimiter', '\t');
        elseif exist(EventsFile, 'file') && isempty(J)
            delete(EventsFile);
        end
        if Output
            BidsInfo.Events = J;
            if isempty(J)
                BidsInfo.Files.Events = '';
            else
                BidsInfo.Files.Events = EventsFile;
            end
        end
    end % if events file exists
    
    % A single events.json file is created in root folder, in BidsBuildStudyFiles. 
    
end


% Format floating-point numbers without trailing zeros.  Works on arrays.
function Out = NumTrim(Num, Precision)
    Precision = 10^Precision;
    Out = round(Precision * Num) / Precision;
    
    % Old string approach.
    %     nNum = numel(Num);
    %     if nNum > 1
    %         Out = '[';
    %     else
    %         Out = '';
    %     end
    %     for i = 1:nNum
    %         Out = [Out, sprintf(['%.', sprintf('%d', Precision), 'f'], Num(i))];
    %         while Out(end) == '0'
    %             Out(end) = '';
    %         end
    %         if Out(end) == '.'
    %             Out(end) = '';
    %         end
    %         if i < nNum
    %             Out = [Out, ','];
    %         end
    %     end
    %     if nNum > 1
    %         Out = [Out, ']'];
    %     end
    %     Out = eval(Out);
end


function [Markers, FileDataset] = openmrk(Dataset, Original, Quiet)
  % Generates a data structure array from MarkerFile.mrk in a CTF dataset.
  %
  % Markers = openmrk(Dataset, Original, Quiet)
  %
  % Each element of the array (each marker) contains the fields: Name, Bit,
  % Count, Samples.  Samples is a (Count x 2) array of marker
  % data which contains trial numbers (indexed from 1) and times (from the
  % start of the trial). It is allowed to give
  % directly a .mrk file instead of a Dataset.
  %
  % Original (open backup marker file) and Quiet (no output on command
  % line) are optional arguments, both false by default.
  %
  % 
  % Copyright 2018 Marc Lalancette
  % The Hospital for Sick Children, Toronto, Canada
  % 
  % This file is part of a free repository of Matlab tools for MEG 
  % data processing and analysis <https://gitlab.com/moo.marc/MMM>.
  % You can redistribute it and/or modify it under the terms of the GNU
  % General Public License as published by the Free Software Foundation,
  % either version 3 of the License, or (at your option) a later version.
  % 
  % This program is distributed WITHOUT ANY WARRANTY. 
  % See the LICENSE file, or <http://www.gnu.org/licenses/> for details.
  % 
  % 2015-01-20
  
  % This field was unnecessary, just make everything editable... [Editable
  % is a boolean that controls whether the marker is editable manually in
  % DataEditor.]
  
  % Parse input arguments.
  if ~exist('Dataset', 'var') || isempty(Dataset)
    Dataset = pwd;
  end
  if ~exist('Original', 'var') || isempty(Original)
    Original = false;
  end
  if ~exist('Quiet', 'var') || isempty(Quiet)
    Quiet = false;
  end
  % Allow specifying the file directly.
  if strcmpi(Dataset(end-3:end), '.mrk')
    MarkerFile = Dataset;
    Dataset = fileparts(Dataset);
  else
    MarkerFile = [Dataset, filesep, 'MarkerFile.mrk'];
  end
  if ~exist(Dataset, 'file') || ~exist(MarkerFile, 'file') || Original
    % See if there was a backup.
    MarkerFileOriginal = [MarkerFile(1:end-4), '_Original.mrk'];
    if exist(MarkerFileOriginal, 'file')
      CopyFile(MarkerFileOriginal, MarkerFile);
      %       if ~copyfile(MarkerFileOriginal, MarkerFile)
      %         error('Copy failed: %s to %s', MarkerFileOriginal, MarkerFile);
      %       end
      if ~Quiet
        fprintf('MarkerFile.mrk restored from %s.\n', MarkerFileOriginal);
      end
    else
      if ~Quiet
        warning('Marker file not found in %s.', Dataset);
      end
      Markers = struct('Name', {}, 'Bit', {}, 'Count', {}, 'Samples', {});
      FileDataset = '';
      return;
    end
  end
  
  % Open file for reading.
  if ~Quiet
    fprintf('Opening marker file: %s\n', MarkerFile);
  end
  fid = fopen(MarkerFile, 'rt', 'ieee-be');
  if (fid == -1)
    error('Failed to open file %s.', MarkerFile);
  end
  
  
  % Prepare string formats.
  FileHeaderFormat = ...
    'PATH OF DATASET:\n';%, ...
  %     '%s\n']; % Dataset name with full path (starting with / on Linux).
  FileHeaderFormat2 = [ ...
    '\n\nNUMBER OF MARKERS:\n', ...
    '%d\n'];%, ... % Number of markers.
  %     '\n\n']; % This brings us to beginning of first CLASSGROUPID line.
  
  % Read file header.  There can be a space in the path or file name so
  % need to use fgetl
  fscanf(fid, FileHeaderFormat, 1); % Finds and goes past that string.
  FileDataset = fgetl(fid);
  %   FileDataset = char(FileDataset'); % Because there were mixed types, it was saved as column of char numbers.
  nMarkers = fscanf(fid, FileHeaderFormat2, 1);
  if isempty(FileDataset) || isempty(nMarkers)
    FileDataset = [];
    nMarkers = 0;
    warning('Error reading marker file header.  Possibly missing header: %s\n', Dataset);
    MissingHeader = true;
    %     Markers = [];
    %     return;
    %     error('Error reading marker file header.  Possibly missing header.');
  else
    MissingHeader = false;
  end
  
  % Read marker data.
  if ~Quiet
    fprintf('Found markers ');
  end
  % Note: no use preallocating the Markers structure since we don't know
  % how many samples we have for each marker.
  %   for m = 1:nMarkers
  m = 1;
  while ~feof(fid)
    Field = fgetl(fid);
    switch Field(1:end-1)
      case 'NAME'
        Line = fgetl(fid);
        Markers(m).Name = sscanf(Line, '%s', 1); %#ok<*AGROW>
      case 'COMMENT'
        Line = fgetl(fid);
        Pattern = 'BitPattern=';
        Index = strfind(Line, Pattern) + length(Pattern);
        if ~isempty(Index)
          Markers(m).Bit = sscanf(Line(Index(1):end), '%i', 1); % Bit # in hexadecimal.
        else
          Pattern = 'bit ';
          Index = strfind(Line, Pattern) + length(Pattern);
          if ~isempty(Index)
            Markers(m).Bit = sscanf(Line(Index(1):end), '%f', 1);
          end
        end
        if ~isfield(Markers, 'Bit') || isempty(Markers(m).Bit) || ...
            ~isnumeric(Markers(m).Bit)
          Markers(m).Bit = 0;
        end
        %       case 'EDITABLE'
        %         Line = fgetl(fid);
        %         Markers(m).Editable = strncmpi(Line, 'Yes', 2);
      case 'BITNUMBER' % Maybe redundant, but this is a proper field, so use it.
        Line = fgetl(fid);
        Markers(m).Bit = sscanf(Line, '%f', 1);
      case 'NUMBER OF SAMPLES'
        Line = fgetl(fid);
        Markers(m).Count = sscanf(Line, '%f', 1);
      case 'LIST OF SAMPLES'
        % Get data
        fgetl(fid); % 'TRIAL NUMBER		TIME FROM SYNC POINT (in seconds)\n'
        Markers(m).Samples = fscanf(fid, '%f', [2, inf])'; % fscanf fills in column order.
        % Trials are indexed from 0 in file, but in CTF programs they are
        % indexed from 1, so add 1 to match what users expect, as well as
        % Matlab indexing.
        if ~isempty(Markers(m).Samples)
          Markers(m).Samples(:, 1) = 1 + Markers(m).Samples(:, 1);
        end
        % Using inf instead of the expected Count brings us past the empty
        % lines, at the start of the next CLASSGROUPID line.  
        %
        % However, if Count is 0, it (sometimes? depending on Matlab
        % version?) also grabs the "C" of that line so we'd need to seek
        % back a character. But when it doesn't grab the "C", seeking back
        % would bring us back on an empty line and break the sequence.  So
        % ignore this for now.
        %         if Markers(m).Count == 0
        %           fseek(fid, -1, 'cof');
        %         end
        if size(Markers(m).Samples, 1) ~= Markers(m).Count
          warning('Number of samples for marker %s doesn''t match expected count.', Markers(m).Name);
          Markers(m).Count = size(Markers(m).Samples, 1);
        end
        if ~Quiet
          fprintf('%s (%1.0f), ', Markers(m).Name, Markers(m).Count);
        end
        m = m + 1;
      case []
        % Safeguard for empty line.  Shouldn't happen, but if it does,
        % don't skip and just move on to the next line.
      otherwise
        fgetl(fid); % Skip other fields.
    end
  end
  
  fclose(fid);
  if ~Quiet
    fprintf('\b\b.\n\n');
  end
  
  if length(Markers) ~= nMarkers
    if MissingHeader
      fprintf('Found %d markers, saving new marker file with header.', numel(Markers));
      savemrk(Markers, Dataset, true);
    else
      warning('Expected %d markers, found %d.', nMarkers, numel(Markers));
    end
  end
  
  
end
