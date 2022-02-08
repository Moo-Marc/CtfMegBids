function [Noise, Found] = BidsFindAssociatedNoise(Recording, BidsInfo, iLog)
%
%
% Found: 0=not found, 1=found by search, 2=existing from AssociatedEmptyRoom, 3=existing provided in BidsInfo.

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
            fprintf(iLog, '  Warning: Ignoring previous or provided noise recording %s for noise recording %s.\n', Noise, RecName);
            Noise = '';
            Found = 0;
        end
        return;
    end
    if isempty(Noise) || ~exist(fullfile(BidsFolder, Noise), 'file')
        if ~isempty(Noise) && ~exist(fullfile(BidsFolder, Noise), 'file')
            fprintf(iLog, '  Warning: Previous/provided noise recording %s not found for %s.\n', Noise, RecName);
            Found = 0;
        end
        % Look in same folder as recording.
        Recordings = BidsRecordings(RecPath, false); % not verbose.
        Recordings(~[Recordings(:).isNoise]) = [];
        % And the emptyroom subject folder.
        Recordings = [Recordings; BidsRecordings(fullfile(BidsFolder, 'sub-emptyroom'), false)];
        NoiseTable = vertcat(Recordings(:).Scan);
        if ~isempty(NoiseTable)
            NoiseDates = NoiseTable.acq_time;
        else
            NoiseDates = [];
        end
        if numel(NoiseDates) < numel(Recordings)
            fprintf(iLog, '  Warning: Missing noise scan.tsv files for %s.\n', RecName);
        end
        %[NoiseDates, Noise, P, S] = BidsScanDates(fullfile(BidsFolder, 'sub-emptyroom'), false); % Don't exclude noise scans.
        if ~isempty(NoiseDates)
            Res4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']);
            Res4 = Bids_ctf_read_res4(Res4File);
            ScanDate = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]);
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
            fprintf(iLog, '  No associated noise recording found for %s.\n', RecName);
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