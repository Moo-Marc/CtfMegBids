function BidsInfo = BidsBuildStudyFiles(BidsFolder, BidsInfo, Overwrite, SaveFiles, RemoveEmptyFields, isEvents)
    % Create BIDS metadata files for a dataset.
    % Satisfies BIDS version indicated at the start of the code below.
    %
    % INPUT:    BidsFolder: Path to the root study folder
    %
    % Authors: Elizabeth Bock, Marc Lalancette, 2017 - 2021-05-18
    
    BIDSVersion = '1.7.0';
    
    if nargin < 5 || isempty(RemoveEmptyFields)
        RemoveEmptyFields = false;
    end    
    if nargin < 4 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 3 || isempty(Overwrite)
        Overwrite = false;
    end
    if nargin < 2 || isempty(BidsInfo)
        BidsInfo = struct();
    end
    if nargin < 6 || isempty(isEvents)
        if isfield(BidsInfo, 'Events')
            isEvents = true;
        else
            isEvents = false;
        end
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

    DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
    if ~exist(DataDescripFile, 'file') || Overwrite || Output
        % Mostly optional fields, see if they're in BidsInfo.
        J.DatasetType = 'raw';
        for Field = {'Name', 'BIDSVersion', 'DatasetType', 'HEDVersion', 'License', 'Authors', 'Acknowledgements', ...
                'HowToAcknowledge', 'Funding', 'EthicsApprovals', 'ReferencesAndLinks', 'DatasetDOI'}
            Field = Field{1}; %#ok<FXSET>
            if isfield(BidsInfo, Field)
                J.(Field) = BidsInfo.(Field);
                if Output
                    BidsInfo = rmfield(BidsInfo, Field);
                end
            elseif isfield(BidsInfo, 'Dataset') && isfield(BidsInfo.Dataset, Field)
                J.(Field) = BidsInfo.Dataset.(Field);
            end
        end
        
        if RemoveEmptyFields
            J = StructTrim(J);
        end
        % Required fields
        if ~isfield(J, 'Name') || isempty(J.Name) 
            if isfield(BidsInfo, 'Study') && ~isempty(BidsInfo.Study)
                J.Name = BidsInfo.Study;
                if Output
                    BidsInfo = rmfield(BidsInfo, 'Study');
                end
            else
                [~, J.Name] = fileparts(BidsFolder); % Often not really appropriate name, but keep for now as it is a required field.
            end
        end
        if ~isfield(J, 'BIDSVersion') || isempty(J.BIDSVersion) 
            J.BIDSVersion = BIDSVersion;
        end
        if SaveFiles
            WriteJson(DataDescripFile, J);
        end
        if Output
            BidsInfo.Dataset = J;
            BidsInfo.Files.Dataset = DataDescripFile;
            BidsInfo.BidsFolder = BidsFolder;
        end
    end
    
    if isfield(BidsInfo, 'Ignore') && ~isempty(BidsInfo.Ignore)
        % create .bidsignore files
        % ignore .log files inside the meg folders
        IgnoreFile = fullfile(BidsFolder, '.bidsignore');
        if (~exist(IgnoreFile, 'file') || Overwrite) && SaveFiles
            Fid = fopen(IgnoreFile, 'w');
            for i = 1:numel(BidsInfo.Ignore)
                fprintf(Fid, '%s\n', BidsInfo.Ignore{i});
            end
            fclose(Fid);
        end
        if Output
            BidsInfo.Files.Ignore = IgnoreFile;
            % BidsInfo.Ignore = BidsInfo.Ignore;
        end
    end
    
    if isEvents 
        EventsJsonFile = fullfile(BidsFolder, 'events.json');
        if ~exist(EventsJsonFile, 'file') || Overwrite || Output
            clear J
            % Column description
            %struct('LongName', '', 'Description', '', 'Levels', struct(), 'Units', '', 'TermURL', '');
            J.onset = struct('Description', 'Event onset time, assuming CTF dataset trials recorded continuously', 'Units', 's');
            %J.duration = struct('Description', 'Duration of the event.');
            J.ds_trial = struct('Description', 'Dataset trial (epoch) in which the event is located in time. First trial is 1.');
            J.sample = struct('Description', 'Sample within the dataset trial (epoch) corresponding to the event onset. First sample is 1.');
            J.value = struct('Description', 'Name of the event.');
            
            if isfield(BidsInfo, 'Events')
                J = StructOverwrite(J, BidsInfo.Events);
            end
            if RemoveEmptyFields
                J = StructTrim(J);
            end
            if SaveFiles
                WriteJson(EventsJsonFile, J);
            end
            if Output
                BidsInfo.Events = J;
                BidsInfo.Files.Events = EventsJsonFile;
            end
        end
    end

end
