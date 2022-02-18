function [Noise, Found, EmptyroomRecordings] = BidsFindAssociatedNoise(Recording, ...
    BidsInfo, iLog, KeepIfNoneFound, Verbose, EmptyroomRecordings, ForceSearch)
%
%
% Found: 0=not found, 1=found by search, 2=existing from AssociatedEmptyRoom, 3=existing provided in BidsInfo.
% KeepIfNoneFound: if true, don't empty Noise entry, even if the file is not found.
% EmptyroomRecordings: can be provided as input, returned as output for efficiency.

if nargin < 7 || isempty(ForceSearch)
    ForceSearch = false;
end
if nargin < 6
    EmptyroomRecordings = [];
end
if nargin < 5 || isempty(Verbose)
    Verbose = true;
end
if nargin < 5 || isempty(KeepIfNoneFound)
    KeepIfNoneFound = true;
end
if nargin < 3 || isempty(iLog)
    iLog = 1; % output messages to command window
end

    [RecPath, RecName, RecExt] = fileparts(Recording);
    isNoise = contains(RecName, 'emptyroom') || strcmpi(BidsInfo.Task, 'noise');

    % Find associated noise recording in BIDS dataset.
    iRelativePath = strfind(RecPath, [filesep, 'sub-']);
    BidsFolder = RecPath(1:iRelativePath(1)-1);
    if isfield(BidsInfo, 'Noise') 
        Noise = char(BidsInfo.Noise); % Converts empty [] to ''.
        Found = 3;
    elseif isfield(BidsInfo, 'Meg') && isfield(BidsInfo.Meg, 'AssociatedEmptyRoom')
        % Check if it was read from a BIDS .json.
        Noise = BidsInfo.Meg.AssociatedEmptyRoom;
        Found = 2;
    else
        Noise = '';
        Found = 0;
    end
    if isNoise 
        if ~isempty(Noise)
            if Verbose
                [~, NoiseName] = fileparts(Noise);
                fprintf(iLog, '  Ignoring previous/provided noise %s.ds for noise recording %s.ds\n', NoiseName, RecName);
            end
            Noise = '';
            Found = 0;
        end
        return;
    end
        
    if isempty(Noise) || ForceSearch || ~exist(fullfile(BidsFolder, Noise), 'file')
        if KeepIfNoneFound
            OldNoise = Noise;
        end
        if ~isempty(Noise) && ~exist(fullfile(BidsFolder, Noise), 'file')
            if Verbose
                [~, NoiseName] = fileparts(Noise);
                fprintf(iLog, '  Previous/provided %s.ds not found for %s.ds\n', NoiseName, RecName);
            end
            Found = 0;
        end
        % Look in same folder as recording.
        Recordings = BidsRecordings(RecPath, false); % not verbose.
        Recordings(~[Recordings(:).isNoise]) = [];
        % And the emptyroom subject folder.
        if isempty(EmptyroomRecordings)
            EmptyroomRecordings = BidsRecordings(fullfile(BidsFolder, 'sub-emptyroom'), false);
        end
        Recordings = [Recordings; EmptyroomRecordings];
        NoiseTable = vertcat(Recordings(:).Scan);
        if ~isempty(NoiseTable)
            NoiseDates = NoiseTable.acq_time;
        else
            NoiseDates = [];
        end
        if numel(NoiseDates) < numel(Recordings)
            fprintf(iLog, '  Warning: Missing noise scan.tsv files for %s.ds\n', RecName);
        end
        %[NoiseDates, Noise, P, S] = BidsScanDates(fullfile(BidsFolder, 'sub-emptyroom'), false); % Don't exclude noise scans.
        if ~isempty(NoiseDates)
            % Could get the date from the scans file instead.
            Res4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']);
            Res4 = Bids_ctf_read_res4(Res4File);
            ScanDate = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]);
            % min returns only one value and index, so if the same noise is both
            % in the subject folder and emptyroom, the former is used.
            [DateDiff, iN] = min(abs(NoiseDates - ScanDate));
            % Check if found a noise scan within 24 hours.
            % Allow night sessions so could be a different date
            if DateDiff < days(1) % && day(NoiseDates(iN)) == day(ScanDate)
                Noise = fullfile(['sub-', Recordings(iN).Subject], ['ses-', Recordings(iN).Session], NoiseTable.filename{iN});
                Found = 1;
            else
                Noise = ''; 
            end
        end
        if isempty(Noise)
            fprintf(iLog, '  No associated noise recording found for %s.ds\n', RecName);
            if KeepIfNoneFound
                Noise = OldNoise;
            end
        end
    end
    if ispc()
        Noise = strrep(Noise, '\', '/');
    end
    
    if ~isempty(Noise) && ~exist(fullfile(BidsFolder, Noise), 'file') % Should not happen
        fprintf(iLog, '  Warning: Noise recording %s not found for %s.\n', Noise, RecName);
        Found = 0;
    end
end