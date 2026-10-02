function [isBids, BidsInfo] = BidsParseRecordingName(FullName, iLog, isWarnings)
    % Extract basic info from file name.
    %
    % [isBids, BidsInfo] = BidsParseRecordingName(FullName, iLog, isWarnings)
    % [isFound, EntityValue] = BidsParseRecordingName(FullName, Entity) [NOT IMPLEMENTED]
    %
    % BIDS: sub-<label>[_ses-<label>]_task-<label>[_acq-<label>][_run-<index>][_proc-<label>]_meg.<manufacturer_specific_extension>
    % In the second usage [NOT YET IMPLEMENTED], Entity is e.g. 'subject', 'session', 'task', etc.
    % (short version of entity names is supported, e.g. 'sub' or 'sub-').
    %
    % Marc Lalancette 2026-09-21

    if nargin < 3 || isempty(isWarnings)
        isWarnings = true;
    end
    if nargin < 2 || isempty(iLog)
        iLog = 1;
        FindEntity = '';
    elseif ischar(iLog)
        error('not yet implemented');
        FindEntity = lower(iLog(1:3));
        iLog = 1;
    end
    
    % Ignore path.
    [Path, Name, Ext] = fileparts(FullName);
    if ~isempty(Path)
        FullName = [Name, Ext];
    end
    
    if strncmp(FullName, 'sub-', 4) %&& ...
            %contains(FullName, '_task-') && ...
            %contains(FullName, '_meg.')
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
        if isempty(ID) && isWarnings
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
                if isWarnings
                    fprintf(iLog, '  Warning: BIDS "proc" name entity not yet supported.\n');
                end
            % case 'meg' % Last part of MEG recording name, do nothing.
            otherwise
                if isWarnings
                    fprintf(iLog, '  Warning: Unrecognized BIDS recording name entity: %s. %s\n', Entity, FullName);
                end
                continue;
        end
    end
    
    if isWarnings && ~isfield(BidsInfo, 'Session')
        warning('Empty session not yet supported.');
    end
            
end