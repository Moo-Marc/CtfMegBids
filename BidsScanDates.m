function [Dates, Files, Subjects, Sessions] = BidsScanDates(BidsFolder, MegOnly, ExcludeNoise, Verbose)
    % Extract scan dates from CTF MEG BIDS dataset.
    %
    % [Dates, Files, Subjects, Sessions] = BidsScanDates(Folder, ExcludeNoise)
    %
    % Marc Lalancette, 2021-04-27
    
    if nargin < 4 || isempty(Verbose)
        Verbose = true;
    end
    if nargin < 3 || isempty(ExcludeNoise)
        ExcludeNoise = true;
    end
    if nargin < 2 || isempty(MegOnly)
        MegOnly = false;
    end
    
    if MegOnly
        % But not really...
        warning('MegOnly may still list other modalities within the same session, then outputs won''t have the same length.');
        % Now use BidsRecordings instead of only looking through _scans.tsv files.
        Recordings = BidsRecordings(BidsFolder, false); % not verbose.
        if ExcludeNoise
            Recordings([Recordings(:).isNoise]) = [];
        end
        Files = vertcat(Recordings(:).Scan);
        Dates = table2array(Files.acq_time);
        Files = table2cell(Files.filename);
        Subjects = {Recordings(:).Subject}';
        Sessions = {Recordings(:).Session}';
    else
        
        % Only looks at first recording in each _scans.tsv file. 
        SubSes = dir(fullfile(BidsFolder, 'sub-*', 'ses-*'));
        nSes = numel(SubSes);
        Sessions = replace({SubSes.name}, 'ses-', '');
        Subjects = {SubSes.folder};
        Subjects = replace(replace(Subjects, [BidsFolder, filesep], ''), 'sub-', '');
        
        % Get session dates.
        Files = cell(nSes, 1);
        Dates = NaT(nSes, 1);
        for iSes = 1:nSes
            ScansFile = fullfile(BidsFolder, ['sub-', Subjects{iSes}], ['ses-', Sessions{iSes}], ...
                ['sub-', Subjects{iSes}, '_ses-', Sessions{iSes}, '_scans.tsv']);
            %             ScansFile = fullfile(BidsFolder, Subjects{iSes}, Sessions{iSes}, ...
            %                 [Subjects{iSes}, '_', Sessions{iSes}, '_scans.tsv']);
            if ~exist(ScansFile, 'file')
                if Verbose
                    fprintf('Warning: Missing scans.tsv file: %s', ScansFile);
                end
            else
                Files{iSes} = ScansFile;
                Scans = ReadScans(ScansFile);
                if ~isempty(Scans.acq_time)
                    Dates(iSes) = Scans.acq_time(1);
                end
            end
        end
    end
end