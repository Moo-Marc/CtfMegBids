function UnknownFiles = Bids_ctf_rename_ds(originalDs, newDsName, newSessionFolder, isAnonymize, sessionDateTime)
% ctf_rename_ds: Renames and/or anonymizes a CTF dataset (.ds)
%
% USAGE:    ctf_rename_ds(originalDs.ds, newDsName.ds);
%           ctf_rename_ds(originalDs.ds, newDsName.ds, newSessionFolder);
%           ctf_rename_ds(originalDs.ds, newDsName.ds, [], 1);
%           ctf_rename_ds(originalDs.ds, newDsName.ds, [], 1, sessionDateTime);
%
% INPUT:    OriginalDs - full path to original ds
%           newSessionFolder - path to new session folder if different from original, ending with '/meg'.
%           newDsName - new name of ds folder, in BIDS format
%           newDsName = ['sub-' SubjectID '_ses-' SessionID '_task-' TaskName '_run-' RunNumb '_meg.ds'];
%           isAnonymize = 0 or 1 (0/false = keep all orig fields, 1/true = remove identifying fields)
%           sessionDateTime = new date [year, month, day] array, with optional additional elements 
%                for [hour, minute, second, millisecond], or [] = use original date/time. 
%                Changing session date/time is only possible when anonymizing.
%
% Anonymization will remove all subject identifying information from the header
% files (names, dates, collection description, operator, run titles); birthdate
% is changed to 1900-01-01 and subject sex is set to 'other'; .bak files are
% deleted, as well as .hist, .newds, processing.cfg.
%
% Without anonymization, only empty .bak files are deleted.
%
% OUTPUT:   new dataset

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2018 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors:  Elizabeth Bock, 2017-2018, Marc Lalancette 2019-2022

% Latest software version validated with this anonymization function.
KnownAcqVersion = 'Acq 6.1.14-beta-el6_8.x86_64-20180116-3847';

% Need CTF read/writeCPersist, in Brainstorm or Fieldtrip externals.
if isempty(which('readCPersist'))
    error('Run BidsSetPath to load required dependencies.');
end

if nargin < 2
    error('Nothing to do.'); % since isAnonimyze is false by default.
end
if nargin < 3
    newSessionFolder = [];
end
if nargin < 4
    isAnonymize = 0;
end
if nargin < 5
    sessionDateTime = [];
end

if ~exist(originalDs, 'dir')
    error('Dataset not found.');
end

[origPath,origName] = fileparts(originalDs);
if isempty(newDsName)
    newName = origName;
    newDsName = [newName, '.ds'];
    if isempty(newSessionFolder)
        newPath = origPath;
    end
else
    [tmp,newName] = fileparts(newDsName);
    newDsName = [newName, '.ds'];
    if isempty(newSessionFolder)
        if ~isempty(tmp)
            newPath = tmp;
        else
            newPath = origPath;
        end
    else
        newPath = newSessionFolder;
    end
end
newDs = fullfile(newPath, newDsName);

% Verify there's something to do.
if strcmp(newPath, origPath) && strcmp(newName, origName)
    if ~isAnonymize
        warning('Nothing to do.');
        return;
    % else: No need to warn that we are overwriting original files, since this
    % function doesn't copy, but moves anyway.
    end
end

% Extract subject, session, etc.
if strcmp(newDsName, 'hz.ds')
    isHz = true;
    Subject = 'hz';
    Task = 'HeadLocalization';
else
    isHz = false;
    [isBids, BidsInfo] = BidsParseRecordingName(newDsName);
    if ~isBids
        error('New dataset name should follow BIDS specification: %s.', newDsName);
    end
    Subject = ['sub-', BidsInfo.Subject];
    RelativePath = fullfile(Subject, ['ses-', BidsInfo.Session], 'meg');
    Task = BidsInfo.Task;
end

% if a new date is given, prepare the different formats for different files
% res4date = '12-May-1891'; %dd-MMM-yyyy
% infodsdate = '18910512114600'; %yyyyMMddHHmmss
% acqdate = '12/05/1891'; %dd/mm/yyyy
if isAnonymize && ~isempty(sessionDateTime)
    ChangeDate = true;
    if numel(sessionDateTime) < 4
        KeepTime = true;
    else
        KeepTime = false;
    end
    sessionDateTime(end+1:6) = 0;
    t = datetime(sessionDateTime);
    DataDate = char(datetime(t, 'Format', 'dd-MMM-yyyy'));
    DataTime = char(datetime(t, 'Format', 'HH:mm'));
    acqdate = char(datetime(t, 'Format', 'dd/MM/yyyy'));
    infodsdate = char(datetime(t, 'Format', 'yyyyMMddHHmmss'));
    xmldate = char(datetime(t, 'Format', 'MM/dd/yy''T''HH:mm:ssZ'));
else
    ChangeDate = false;
end
AnonBirthDate = char(datetime([1900 1 1 0 0 0], 'Format', 'yyyyMMddHHmmss'));


%% rename the parent ds folders
% Check if name or path changed, otherwise no move needed (but possibly anonimization).
if ~strcmp(newDs, originalDs)
    % Must check if exists, otherwise would move a duplicate inside newDs.
    if exist(newDs, 'dir')
        % Move all files inside dataset.
        movefile(fullfile(originalDs, '*'), newDs);
        % Delete empty original dataset folder.
        rmdir(originalDs);
    else
        % Rename dataset folder.
        movefile(originalDs, newDs);
    end
end

%% rename files inside parent folder if needed
if ~strcmp(newName, origName)
    files = dir(fullfile(newDs, [origName '*']));
    for iFiles = 1:length(files)
        repName = strrep(files(iFiles).name, origName, newName);
        movefile(fullfile(newDs,files(iFiles).name), fullfile(newDs,repName));
    end
end

%% Check for unknown files
ExpectedFiles = dir(fullfile(newDs, [newName '*']));
ExpectedFiles = [{ExpectedFiles.name}'; ...
    {'processing.cfg'; 'processing.cfg.bak'; ...
    'ClassFile.cls'; 'ClassFile.cls.bak'; ...
    'MarkerFile.mrk'; 'MarkerFile.mrk.bak'; ...
    'default.de'; 'default.de.bak'; ...
    'bad.segments'; 'bad.segments.bak'; ...
    'BadChannels'; 'BadChannels.bak'; ...
    'ChannelGroupSet.cfg'; 'ChannelGroupSet.cfg.bak'; ...
    'VirtualChannels'; 'VirtualChannels.bak'; ...
    'DigTrigChannelInfo.txt'; 'DigTrigChannelInfo.txt.bak'; ...
    'params.dsc'; 'params.dsc.bak'; ...
    'hz.ds'; '.'; '..'}];
UnknownFiles = dir(fullfile(newDs, '*'));
[~, iU] = setdiff({UnknownFiles.name}', ExpectedFiles);
UnknownFiles = UnknownFiles(iU);
if ~isempty(iU)
    warning('Unknown files in %s', newDs);
    disp(UnknownFiles.name);
end

%% Delete unnecessary files

% empty (or all) backup files
BakFiles = dir(fullfile(newDs, '*.bak'));
for iFiles = 1:numel(BakFiles)
    if isAnonymize || BakFiles(iFiles).bytes == 0
        delete(fullfile(newDs, BakFiles(iFiles).name));
    end
end

if isAnonymize 
    % VirtualChannels
    delete(fullfile(newDs, 'VirtualChannels*'));
    delete(fullfile(newDs, 'DigTrigChannelInfo*')); % Same format as VirtualChannels.
    
    % processing.cfg
    % Text file used to apply balancing and filters with CTF software, possibly
    % represents the viewing filters in DataEditor/Acq?
    % Includes a date (study defaults save date?) that would give a lower bound for the scan date.
    
    % ChannelGroupSet.cfg
    % Text file for defining channel groups and display options in CTF software.
    % Includes a date (study defaults save date?) that would give a lower bound for the scan date.
    delete(fullfile(newDs, '*.cfg'));
    
    % .newds
    delete(fullfile(newDs, '*.newds'));
    
    % default.de
    delete(fullfile(newDs, 'default.de*'));

    % params.dsc
    % Text file "head localization parameters". Includes a date.
    delete(fullfile(newDs, '*.dsc'));
end

% Could also delete hz*.ds
% sub-dataset of initial (and possibly additional) head localization(s)

% Empty .eeg
EegFiles = dir(fullfile(newDs, '*.eeg'));
for iFiles = 1:numel(EegFiles)
    if EegFiles(iFiles).bytes == 0
        delete(fullfile(newDs, EegFiles(iFiles).name));
    end
end


%% other files that do not need to be accessed
% *.eeg
% text file with list of EEG channels and locations (if updated)

% *.hc
% text file with head position information

% *.meg4
% binary file that contains the MEG sensor data

%% *.hist
if isAnonymize
    % for anon: run title, date, time
    % delete the .hist file
    delete(fullfile(newDs, '*.hist'));
else
    % append new dataset name?
    histFile = dir(fullfile(newDs, '*.hist'));
    if numel(histFile) > 1
        warning('Multiple history files found in %s', newDs);
        histFile(2:end) = [];
    end
    if ~isempty(histFile)
        Fid = FileOpen(fullfile(newDs, histFile.name),'r');
        f=fread(Fid,'*char')';
        fclose(Fid);
        f = strrep(f,origName,newName);
        Fid  = FileOpen(fullfile(newDs, histFile.name),'w');
        fprintf(Fid,'%s',f);
        fclose(Fid);
    end
end

%% ClassFile.cls
% change PATH OF DATASET
clsFile = dir(fullfile(newDs, '*.cls'));
if numel(clsFile) > 1
    warning('Multiple class files found in %s', newDs);
    clsFile(2:end) = [];
end
if ~isempty(clsFile)
    if isHz && isAnonymize
        % Just delete, shouldn't exist anyway?
        delete(fullfile(newDs, clsFile.name));
    else
        Fid  = FileOpen(fullfile(newDs, clsFile.name),'r');
        f=fread(Fid,'*char')';
        fclose(Fid);
        newlineInd = regexp(f,'\n');
        oldstr = f(newlineInd(1)+1:newlineInd(2)-1);
        f = strrep(f,oldstr,fullfile(RelativePath, newDsName));
        Fid  = FileOpen(fullfile(newDs, clsFile.name),'w');
        fprintf(Fid,'%s',f);
        fclose(Fid);
    end
end

%% MarkerFile.mrk
% change PATH OF DATASET
mrkFile = dir(fullfile(newDs, '*.mrk'));
if numel(mrkFile) > 1
    warning('Multiple marker files found in %s', newDs);
    mrkFile(2:end) = [];
end
if ~isempty(mrkFile)
    if isHz && isAnonymize
        % Just delete, shouldn't exist anyway?
        delete(fullfile(newDs, mrkFile.name));
    else
        Fid  = FileOpen(fullfile(newDs, mrkFile.name),'r');
        f=fread(Fid,'*char')';
        fclose(Fid);
        newlineInd = regexp(f,'\n');
        oldstr = f(newlineInd(1)+1:newlineInd(2)-1);
        f = strrep(f,oldstr,fullfile(RelativePath, newDsName));
        Fid  = FileOpen(fullfile(newDs, mrkFile.name),'w');
        fprintf(Fid,'%s',f);
        fclose(Fid);
    end
end

%% *.acq
% for anon: run title, date, time and description
if isAnonymize
    acqFile = dir(fullfile(newDs, '*.acq'));
    if numel(acqFile) > 1
        warning('Multiple acq files found in %s', newDs);
        acqFile(2:end) = [];
    end
    if ~isempty(acqFile)
        % read the file
        acqTag=readCPersist(fullfile(newDs,acqFile.name),0);
        
        if isAnonymize
            nameTag = find(cellfun(@(c)~isempty(find(c,1)), regexp({acqTag.name},'_run_title')));
            acqTag(nameTag(1)).data = Task;
            nameTag = find(cellfun(@(c)~isempty(find(c,1)), regexp({acqTag.name},'_run_description')));
            acqTag(nameTag(1)).data = Task;
            if ChangeDate
                nameTag = find(cellfun(@(c)~isempty(find(c,1)), regexp({acqTag.name},'_run_date')));
                acqTag(nameTag(1)).data = acqdate;
            end
        end
        
        % save changes
        writeCPersist(fullfile(newDs,acqFile.name),acqTag);
    end
end

%% *.infods
infoDs = dir(fullfile(newDs, '*.infods'));
if numel(infoDs) > 1
    warning('Multiple infods files found in %s', newDs);
    infoDs(2:end) = [];
end
if ~isempty(infoDs) && (isAnonymize || ChangeDate)
    % read file
    CPersistObj = readCPersist(fullfile(newDs,infoDs.name),0);
    
    if ChangeDate
        % Replace dates
        Tags = {'_DATASET_UID', '_DATASET_PATIENTUID', '_DATASET_PROCEDUREUID', '_PATIENT_UID', '_PROCEDURE_UID'};
        DataFun = @(Data) [Data(1:23), infodsdate, Data(38:end)];
        CPersistObj = UpdateCPercist(CPersistObj, Tags, DataFun);
        
        Tags = {'_PROCEDURE_STARTEDDATETIME', '_PROCEDURE_CLOSEDDATETIME'};
        CPersistObj = UpdateCPercist(CPersistObj, Tags, infodsdate);
        Tags = {'_DATASET_CREATORDATETIME', '_DATASET_LASTMODIFIEDDATETIME', '_DATASET_COLLECTIONDATETIME'};
        CPersistObj = UpdateCPercist(CPersistObj, Tags, infodsdate);
    end
    
    if isAnonymize
        Tags = {'_PATIENT_BIRTHDATE'};
        CPersistObj = UpdateCPercist(CPersistObj, Tags, AnonBirthDate);
        
        % Default values
        CPersistObj = UpdateCPercist(CPersistObj, {'_PATIENT_SEX'}, '2');
        CPersistObj = UpdateCPercist(CPersistObj, {'_PROCEDURE_ACCESSIONNUMBER'}, '0');
        CPersistObj = UpdateCPercist(CPersistObj, {'_PROCEDURE_LOCATION'}, '/ACQ_Data/0.proc');
        
        % Empty
        Tags = {'_PATIENT_NAME_FIRST', '_PATIENT_NAME_MIDDLE', '_PATIENT_NAME_LAST', '_PATIENT_PACS_NAME', '_PATIENT_PACS_UID', ...
            '_DATASET_COMMENTS', '_DATASET_KEYWORDS', '_DATASET_OPERATORNAME', ...
            '_PROCEDURE_COMMENTS'};
        CPersistObj = UpdateCPercist(CPersistObj, Tags, []);
        
        % New values
        CPersistObj = UpdateCPercist(CPersistObj, {'_PATIENT_ID'}, Subject);
        CPersistObj = UpdateCPercist(CPersistObj, {'_PROCEDURE_TITLE', '_DATASET_PROCSTEPTITLE', '_DATASET_PROCSTEPPROTOCOL', '_DATASET_PROCSTEPDESCRIPTION'}, Task, false); % don't warn for null _procStepDescription
        CPersistObj = UpdateCPercist(CPersistObj, {'_DATASET_RPFILE'}, [Task, '.rp']);
    end
    
    % save changes        
    writeCPersist(fullfile(newDs,infoDs.name),CPersistObj)
end

%% *.res4
% binary file that contains dataset info including the following
% identifying fields:
% nfSetUp.nf_run_name, nfSetUp.nf_run_title, nfSetUp.nf_instruments, nfSetUp.nf_collect_descriptor, nfSetUp.nf_subject_id, nfSetUp.nf_operator
res4File = dir(fullfile(newDs, '*.res4'));
isQuiet = true; % Avoid date/time bug warnings that we fix here anyway.
[res4Info, DateBug] = Bids_ctf_read_res4(fullfile(newDs,res4File.name), isQuiet);
if ChangeDate && KeepTime
    DataTime = res4Info.res4.data_time;
end
if isAnonymize 
    if ChangeDate
        % Use null instead of empty to force erasing.
        ctf_edit_res4(newDs, Subject, Task, char(0), DataTime, DataDate);
    else
        ctf_edit_res4(newDs, Subject, Task, char(0), res4Info.res4.data_time, res4Info.res4.data_date);
    end
elseif DateBug
    % Fix some possible bugs in date and time.
    ctf_edit_res4(newDs, [], [], [], res4Info.res4.data_time, res4Info.res4.data_date);
end

%% .xml (new file in beta software)
if isAnonymize
    XmlFile = dir(fullfile(newDs, '*.xml'));
    if numel(XmlFile) > 1
        warning('Multiple xml files found in %s', newDs);
        XmlFile(2:end) = [];
    end
    if ~isempty(XmlFile)
        XmlFile = fullfile(newDs, XmlFile(1).name); % presume only 1 for now.
        XmlObj = xmlread(XmlFile);
        % Verify version and warn if newer than we know.
        List = XmlObj.getElementsByTagName('_collectionSoftware');
        Item = List.item(0).getFirstChild;
        if isempty(Item)
            error('Null _collectionSoftware tag; couldn''t verify version');
        end
        AcqVersion = char(Item.getData);
        if CheckNewerVersion(AcqVersion, KnownAcqVersion)
            error('The dataset version is newer than this anonymization function. The function needs to be updated.');
        end
            
        if ChangeDate
            % Replace dates
            Tags = {'_UID', '_patientUID', '_procedureUID'};
            DataFun = @(Data) [Data(1:23), infodsdate, Data(38:end)];
            XmlObj = UpdateXml(XmlObj, Tags, DataFun);
            
            Tags = {'_startedDateTime', '_closedDateTime'};
            XmlObj = UpdateXml(XmlObj, Tags, infodsdate);
            Tags = {'_creatorDateTime', '_lastModifiedDateTime', '_collectionDatTime', '_collectionDateTime'};
            XmlObj = UpdateXml(XmlObj, Tags, xmldate);
            Tags = {'_dataTime'};
            XmlObj = UpdateXml(XmlObj, Tags, DataTime);
            Tags = {'_dataDate'};
            XmlObj = UpdateXml(XmlObj, Tags, DataDate);
        end
        
        Tags = {'_birthDate'};
        XmlObj = UpdateXml(XmlObj, Tags, AnonBirthDate);
        
        % Default values
        XmlObj = UpdateXml(XmlObj, {'_sex'}, '2');
        XmlObj = UpdateXml(XmlObj, {'_accessionNumber'}, '0');
        XmlObj = UpdateXml(XmlObj, {'_location'}, '/ACQ_Data/0.proc');
        
        % Empty
        Tags = {'_firstName', '_middleName', '_lastName', '_pacsName', '_pacsUID', '_comments', '_keywords', '_operatorName'};
        XmlObj = UpdateXml(XmlObj, Tags, []);
        
        % New values
        XmlObj = UpdateXml(XmlObj, {'_id'}, Subject);
        XmlObj = UpdateXml(XmlObj, {'_title', '_procStepTitle', '_procStepProtocol', '_procStepDescription'}, Task, false); % don't warn for null _procStepDescription
        XmlObj = UpdateXml(XmlObj, {'_rpFile'}, [Task, '.rp']);
        
        % New dataset name for all meg4 files (.meg4, .1_meg4, etc)
        Tags = {'_file'};
        GetExtRegexp = '(\.[^\\/.]+)$';
        DataFun = @(Data) fullfile('.', [newDsName, regexp(Data, GetExtRegexp, 'match', 'once')]);
        XmlObj = UpdateXml(XmlObj, Tags, DataFun);
        
        xmlwrite(XmlFile, XmlObj);
    end
end

end

% ===== Anonymize RES4 file =====
function ctf_edit_res4(ds_dir, subject_id, run_title, operator, data_time, data_date, verbose)
if nargin < 7
    verbose = false;
end
% List res4 files
dslist = dir(fullfile(ds_dir, '*.res4'));
if isempty(dslist)
    error('Cannot find res4 file.');
end
% Get res4 file
res4_file = fullfile(ds_dir, dslist(1).name);
if verbose
    disp(['Editing file: ' res4_file]);
end

% Open .res4 file (Big-endian byte ordering)
Fid = fopen(res4_file, 'r+', 'b');
if Fid < 0
    error('Could not open res4 file: %s', res4_file);
end
% Subject id
if (nargin >= 2) && ~isempty(subject_id)
    res4_write_string(Fid, subject_id, 1712, 32);
    if verbose
        disp(['   > subject_id = ' subject_id]);
    end
end
% Run title
if (nargin >= 3) && ~isempty(run_title)
    res4_write_string(Fid, run_title, 1392, 256);
    if verbose
        disp(['   > run_title  = ' run_title]);
    end
    % run name
    res4_write_string(Fid, run_title, 1360, 32);
    % nf_collect_descriptor
    res4_write_string(Fid, run_title, 1680, 32);
    % nf_run_descriptor
    if (fseek(Fid, 1836, 'bof') == -1)
        fclose(Fid);
        error('Cannot go to byte #%d.', offset);
    end
    rdlen = fread(Fid, 1, 'int32');
    res4_write_string(Fid, run_title, 1844, rdlen);
end
% Operator
if (nargin >= 4) && ~isempty(operator)
    res4_write_string(Fid, operator, 1744, 32);
    if verbose
        disp(['   > operator   = ' operator]);
    end
end
% Time
if (nargin >= 5) && ~isempty(data_time)
    res4_write_string(Fid, data_time, 778, 255);
    if verbose
        disp(['   > data_time  = ' data_time]);
    end
end
% Date
if (nargin >= 6) && ~isempty(data_date)
    res4_write_string(Fid, data_date, 1033, 255);
    if verbose
        disp(['   > data_date  = ' data_date]);
    end
end

% Close file
fclose(Fid);

% meg41GeneralResRec (offset: 8)
% CStr256 appName; 8 ' '
% CStr256 dataOrigin; 264 ' '
% CStr256 dataDescription; 520 ' '
% Int16 no_trials_avgd; 776
% CChar data_time[255]; 778
% CChar data_date[255]; 1033
% new_general_setup_rec_ext gSetUp; 1288
% meg4FileSetup nfSetUp; 1360

% new_general_setup_rec_ext (len: 72)
% 4+2+2_+ 8+8+ 2+2_+4+ 2+2+4+ union(10,8)=10 + 2_+2+2_+ 4+2+2_+ 4+4

% meg4FileSetup
% CChar nf_run_name[32], 1360 ' '
% nf_run_title[256], 1392
% nf_instruments[32], 1648 ' '
% nf_collect_descriptor[32], 1680 
% nf_subject_id[32], 1712
% nf_operator[32], 1744
% nf_sensorFileName[56]; 1776 ' '
%There is a bug in the documentation, the padding is before rdlen/size:
% long reserved1; /* pad out to the next 8 byte boundary */ 1832
% Int32 size; /* length of following array (run_description) */ 1836
% CStrPtr nf_run_descriptor; 1840
% The offsets indicated in the table show "genres" should finish at 1840, so unclear.

% run description (offset: 1844, rdlen bytes)
end

% ===== WRITE STRING IN RES4 =====
function res4_write_string(Fid, value, offset, n)
    % Trim string
    if (length(value) > n)
        value = value(1:n);
    end
    % Create padded string
    str = char(zeros(1,n));
    str(1:length(value)) = value;
    % Write string
    if (fseek(Fid, offset, 'bof') == -1)
        fclose(Fid);
        error('Cannot go to byte #%d.', offset);
    end
    if (fwrite(Fid, str, 'char') < n)
        fclose(Fid);
        error('Cannot write data to file.');
    end
end

function Status = CheckNewerVersion(Ver, KnownVer)
    Status = false;
    Ver = ExtractVersion(Ver);
    KnownVer = ExtractVersion(KnownVer);
    nV = max(numel(Ver), numel(KnownVer));
    if isempty(nV) || nV == 0
        error('Unrecognized Acq version string.');
    end
    for iV = 1:nV
        if Ver(iV) > KnownVer(iV)
            Status = true;
            return;
        end
    end
    
    function V = ExtractVersion(VChar)
        if ~strcmp(VChar(1:4), 'Acq ')
            error('Unrecognized Acq version string.');
        end
        VChar(1:4) = '';
        V = [];
        while true
            [VTest, VChar] = strtok(VChar, '.-'); %#ok<STTOK>
            V(end+1) = str2double(VTest); %#ok<AGROW>
            if isnan(V(end))
                V(end) = [];
                break;
            end
        end
    end
end


