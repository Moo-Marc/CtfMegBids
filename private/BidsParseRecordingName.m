function [isBids, BidsInfo] = BidsParseRecordingName(FullName, iLog, WarnEmptySession)
    % Extract basic info from file name.
    % BIDS: sub-<label>[_ses-<label>]_task-<label>[_acq-<label>][_run-<index>][_proc-<label>]_meg.<manufacturer_specific_extension>
    if nargin < 3 || isempty(WarnEmptySession)
        WarnEmptySession = true;
    end
    if nargin < 2 || isempty(iLog)
        iLog = 1;
    end
    
    % Check if path was passed by mistake.
    [Path, Name, Ext] = fileparts(FullName);
    if ~isempty(Path)
        FullName = [Name, Ext];
    end
    
    if strncmp(FullName, 'sub-', 4) && ...
            contains(FullName, '_task-') && ...
            contains(FullName, '_meg.')
        isBids = true;
    else
        isBids = false;
        BidsInfo = struct();
        return;
    end
    
    Name = strrep(FullName, '_meg.ds', '');
    while ~isempty(Name)
        [Entity, Name] = strtok(Name, '-_'); %#ok<*STTOK>
        [ID, Name] = strtok(Name, '-_');
        if isempty(ID)
            fprintf(iLog, '  Warning: Empty BIDS recording name part: %s.\n', Entity);
        end
        switch Entity
            case 'sub'
                BidsInfo.Subject = ID;
            case 'ses'
                BidsInfo.Session = ID;
            case 'task'
                BidsInfo.Task = ID;
            case 'acq'
                BidsInfo.Acq = ID;
            case 'run'
                BidsInfo.Run = ID;
            case 'proc'
                %BidsInfo.Proc = ID;
                fprintf(iLog, '  Warning: BIDS "proc" name entity not yet supported.\n');
            % case 'meg' % Last part of MEG recording name, do nothing.
            otherwise
                fprintf(iLog, '  Error: Unrecognized BIDS recording name entity: %s. %s\n', Entity, FullName);
                continue;
        end
    end
    
    if WarnEmptySession && ~isfield(BidsInfo, 'Session')
        warning('Empty session not yet supported.');
    end
            
end