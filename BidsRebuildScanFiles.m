function [Recordings, Message] = BidsRebuildScanFiles(...
        BidsFolder, Verbose, SaveFiles, SkipBuild, OldRecordings)
    % Rebuild BIDS scans.tsv files.
    %
    % BidsFolder must be the root study folder, not a subject or session
    % for example.
    %
    % If SaveFiles is false (default true), no files are modified.  This can be
    % used with Verbose = true to perform a dry run and see in details what
    % would get changed.
    %
    % Marc Lalancette 2019-2024
    
    if nargin < 4 || isempty(SkipBuild)
        SkipBuild = false;
    end
    if nargin < 3 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 2 || isempty(Verbose)
        Verbose = false;
    end
    if nargin < 1 || isempty(BidsFolder)
        error('BidsFolder input required.')
    end
    
    if SaveFiles
        Overwrite = true;
    else
        Overwrite = false;
    end
    
    Message = {};
    if ~SaveFiles
        Message{end+1} = sprintf('\n----- Dry run selected.  No files will be modified. -----\n');
        fprintf(Message{end});
    end
    
    % First get the old metadata. Returns noise recordings first, which is
    % needed here to regenerate the noise scans.tsv before other
    % recordings (for noise matching).
    if nargin < 5 || isempty(OldRecordings)
        OldRecordings = BidsRecordings(BidsFolder, false, true); % not Verbose, NoiseFirst
    else
        nR = numel(OldRecordings);
    end
    
    % --------------------------------------------------------
    % Recordings   
    if ~SkipBuild
        % Rebuild and compare, including scans tables.
        %     Recordings = [];
        %     Recordings(nR) = struct('Name', '', 'Folder', '', 'Subject', '', 'Session', '', ...
        %         'Task', '', 'Acq', '', 'Run', '', 'Scan', struct('AcqDate', datetime()), ...
        %         'Meg', struct(), 'CoordSystem', struct(), 'Channels', table(), 'Files', struct());
        %     Recordings(nR) = struct('Subject', '', 'Session', '', 'Task', '', ...
        %         'Meg', struct(), 'CoordSystem', struct(), 'Channels', table(), 'Files', struct());
        for r = 1:nR
            Recording = fullfile(BidsFolder, OldRecordings(r).Folder, OldRecordings(r).Name);
            if Verbose
                fprintf('Processing recording %d: %s.\n', r, Recording);
            end
            Recordings(r) = BidsBuildSessionFiles(Recording, [], Overwrite, SaveFiles);
            % Overwrite for session does not replace the file, but the entry.
            if r == 1
                % Initialize full structure.
                Recordings(nR) = Recordings(1);
            end
            if Verbose
                NewMessage = BidsCompare(OldRecordings(r), Recordings(r), sprintf('Recordings(%d)', r));
                if ~isempty(NewMessage)
                    Message{end+1} = sprintf('All changes, %s\n', Recordings(r).Name);
                    fprintf(Message{end});
                    for m = 1:numel(NewMessage)
                        Message{end+1} = NewMessage{m};%     Scans = vertcat(Recordings.Scan); % This doesn't work if there are missing ones.
                        fprintf(Message{end});
                    end
                end
            end
        end
    else
        Recordings = OldRecordings;
    end
        
    % --------------------------------------------------------
    % Scans tables
    
    % Look for extra scans files, e.g. in subject folder or with wrong
    % name, or extra or duplicate recordings.

    % Make a single table with recordings scan info, including the scans.tsv file names.
    % This doesn't work if there are missing ones.  BidsRecordings modified
    % to never be empty.
    Scans = vertcat(Recordings.Scan); 
    if size(Scans, 1) ~= nR
        error('Unexpected number of scans, maybe BidsBuildSessionFiles problem.');
    end
    ScansFiles = arrayfun(@(x) x.Files.Scans, Recordings, 'UniformOutput', false)';
    OldScansFiles = dir(fullfile(BidsFolder, '**', '*scans.tsv'));
    for f = 1:numel(OldScansFiles)
        OldScansFile = fullfile(OldScansFiles(f).folder, OldScansFiles(f).name);
        if ~ismember(OldScansFile, ScansFiles)
            if SaveFiles
                delete(OldScansFile);
                Message{end+1} = sprintf('Deleting scans file %s\n', OldScansFile);
                fprintf(Message{end});
            elseif Verbose
                Message{end+1} = sprintf('Extra scans file: %s\n', OldScansFile);
                fprintf(Message{end});
            end
        else
            iScans = find(strcmp(OldScansFile, ScansFiles)); % never empty because ismember.
            OldScans = ReadScans(OldScansFile);
            % Sort in chronological order for comparison.
            TempScans = sortrows(Scans(iScans, :), {'acq_time', 'filename'});
            % Check for extras or duplicates.  Dates were already updated
            % and compared above.
            if SaveFiles && ( numel(OldScans.filename) ~= numel(iScans) || ...
                    any(~ismember(OldScans.filename, Scans.filename(iScans))) )
                % Write sorted in chronological order.  This means a file may
                % get saved without verbose indicating any changes.
                WriteScans(OldScansFile, TempScans);
            end
            if Verbose
                NewMessage = BidsCompare(OldScans, TempScans, 'Scans');
                if ~isempty(NewMessage)
                    Message{end+1} = sprintf('Extra or duplicate scans, %s\n', OldScansFile);
                    fprintf(Message{end});
                    for m = 1:numel(NewMessage)
                        Message{end+1} = NewMessage{m};
                        fprintf(Message{end});
                    end
                end
            end
        end
    end
    
end

