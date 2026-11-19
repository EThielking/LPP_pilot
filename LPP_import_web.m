function [Info, matFile, Web] = LPP_import_web(inputFile, outputRoot)
% Import one typed-response web backup into the laboratory Info structure
% Run LPP_import_web with no arguments and select the downloaded JSON file
% All additional web timing, delivery, and practice details stay in Web
% This function does not require Psychtoolbox or a transcription service

if nargin < 1 || isempty(inputFile)
    [name, folder] = uigetfile({'*.json','LPP JSON backup'}, ...
        'Select one participant backup');
    if isequal(name,0), Info = []; matFile = ''; Web = []; return; end
    inputFile = fullfile(folder,name);
end
inputFile = char(string(inputFile));
if isfolder(inputFile), inputFile = fullfile(inputFile,'session.json'); end
assert(isfile(inputFile),'LPP:MissingFile','Cannot find %s',inputFile);
sourceFile = inputFile;
[sourceFolder,~,~] = fileparts(inputFile);
session = jsondecode(fileread(inputFile));
if isfield(session,'session') && ~isfield(session,'participant_id')
    session = session.session;
end
assert(isstruct(session) && isscalar(session),'LPP:BackupFormat','Invalid session JSON');
assert(isfield(session,'participant_id') && isfield(session,'sections'), ...
    'LPP:BackupFormat','This is not a typed LPP session backup');
assert(strcmp(text(session,'protocol'),'lpp-typed'),'LPP:Protocol', ...
    'Select a typed LPP backup, not an earlier spoken-response backup');
pid = char(string(session.participant_id));
assert(~isempty(regexp(pid,'^[A-Za-z0-9_-]{1,64}$','once')), ...
    'LPP:ParticipantID','Invalid participant ID in backup');
if nargin < 2 || isempty(outputRoot)
    macRoot = '/Users/EMT/Projects/LPP/LPP_web';
    if isfolder(macRoot), outputRoot = fullfile(macRoot,'data_lpp');
    else, outputRoot = fullfile(sourceFolder,'data_lpp'); end
end
outputRoot = char(string(outputRoot));

plan = getPlan(session);
sectionNumbers = arrayfun(@(s) number(s,'section'),plan);
assert(all(isfinite(sectionNumbers)) && all(ismember(sectionNumbers,1:9)) && ...
    numel(unique(sectionNumbers))==numel(sectionNumbers), ...
    'LPP:Plan','Section plan must contain unique section numbers from 1 to 9');
assert(issorted(sectionNumbers),'LPP:Plan','Sections must follow story order');
actual = asStructArray(session.sections);
assert(numel(unique(arrayfun(@(s) number(s,'section'),actual)))==numel(actual), ...
    'LPP:DuplicateSection','Duplicate section records in backup');
assert(all(ismember(arrayfun(@(s) number(s,'section'),actual),sectionNumbers)), ...
    'LPP:UnknownSection','A saved section is absent from the plan');

% The laboratory leaves startTime empty if the audiobook never begins
Info = struct('subjectID',pid,'startTime',labTime(text(session,'storyStartISO')), ...
    'endTime',labTime(text(session,'endISO')), ...
    'audiobookFile',strings(1,numel(plan)),'probeTimes',zeros(0,1), ...
    'completedProbes',0);
trialTemplate = struct('probeNumber',NaN,'section',NaN,'probePhrase',"", ...
    'recallResponse',"",'onTask',NaN,'KSS',NaN,'recallTarget',"", ...
    'cue',"",'recallRT',NaN,'KSSRT',NaN,'onTaskRT',NaN);
Info.trials = repmat(trialTemplate,1,0);
questionTemplate = struct('section',NaN,'questionNumber',NaN, ...
    'question','','options',{{}},'correctAnswer',NaN,'response',NaN, ...
    'correct',NaN,'responseTime',NaN,'RT',NaN,'confidence',NaN,'confidenceRT',NaN);
Info.comprehension = repmat(questionTemplate,1,0);
completed = false(1,0);
webTrialIndex = repmat(struct('globalProbeNumber',NaN,'section',NaN, ...
    'sectionProbeNumber',NaN,'status','','probeToRecallEnd_sec',NaN),1,0);

for k = 1:numel(plan)
    spec = plan(k);
    section = sectionNumbers(k);
    Info.audiobookFile(k) = string(text(spec,'audiobookFile'));
    assert(strlength(Info.audiobookFile(k))>0,'LPP:Plan','Missing audiobook filename');
    probes = asStructArray(spec.probes);
    assert(~isempty(probes),'LPP:Plan','Section %d has no planned probes',section);
    record = actual(arrayfun(@(s) number(s,'section')==section,actual));
    if isempty(record), savedTrials = struct([]); savedQuestions = struct([]);
    else
        savedTrials = asStructArray(field(record,'trials',struct([])));
        savedQuestions = asStructArray(field(record,'comprehension',struct([])));
    end
    localNumbers = arrayfun(@(s) number(s,'probeNumber'),savedTrials);
    assert(all(ismember(localNumbers,1:numel(probes))) && ...
        numel(unique(localNumbers))==numel(localNumbers), ...
        'LPP:DuplicateProbe','Invalid or duplicate probe in section %d',section);
    for j = 1:numel(probes)
        p = probes(j);
        assert(number(p,'probeNumber')==j,'LPP:Plan','Planned probe numbers must be consecutive within each section');
        t = trialTemplate;
        n = numel(Info.trials)+1;
        t.probeNumber = n;
        t.section = section;
        t.probePhrase = string(text(p,'recallSegment',text(p,'probePhrase')));
        t.recallTarget = string(text(p,'recallTarget'));
        t.cue = string(text(p,'cue'));
        probeTime = number(p,'probe_sec');
        assert(isfinite(probeTime) && probeTime>0,'LPP:Plan','Missing source probe time');
        Info.probeTimes(end+1,1) = probeTime;
        hit = savedTrials(localNumbers==j);
        done = false;
        status = 'not_started';
        totalTime = NaN;
        if ~isempty(hit)
            for immutable = {'cue','recallTarget'}
                key = immutable{1};
                if isfield(hit,key)
                    assert(strcmp(text(hit,key),char(t.(key))), ...
                        'LPP:PlanMismatch','Saved %s differs from section %d probe %d',key,section,j);
                end
            end
            t.recallResponse = strtrim(string(text(hit,'recallResponse')));
            t.onTask = number(hit,'onTask');
            t.KSS = number(hit,'KSS');
            t.recallRT = number(hit,'recallRT');
            t.KSSRT = number(hit,'KSSRT');
            t.onTaskRT = number(hit,'onTaskRT');
            status = text(hit,'status','partial');
            done = strcmp(status,'complete');
            totalTime = number(hit,'probeToRecallEnd_sec');
            validateTrial(t,done);
        end
        Info.trials(n) = t;
        completed(n) = done;
        webTrialIndex(n) = struct('globalProbeNumber',n,'section',section, ...
            'sectionProbeNumber',j,'status',status,'probeToRecallEnd_sec',totalTime);
    end
    questionNumbers = arrayfun(@(q) number(q,'questionNumber'),savedQuestions);
    assert(all(isfinite(questionNumbers)) && all(questionNumbers>=1) && ...
        all(questionNumbers==fix(questionNumbers)) && ...
        numel(unique(questionNumbers))==numel(questionNumbers), ...
        'LPP:Question','Invalid or repeated comprehension question');
    [~,order] = sort(questionNumbers);
    plannedQuestions = asStructArray(field(spec,'questions',struct([])));
    for j = reshape(order,1,[])
        q = savedQuestions(j);
        c = questionTemplate;
        c.section = section;
        c.questionNumber = number(q,'questionNumber');
        c.question = text(q,'question');
        c.options = reshape(cellstr(string(field(q,'options',{}))),1,[]);
        assert(numel(c.options)==4,'LPP:Question','Expected four answer options');
        for key = {'correctAnswer','response','responseTime','RT','confidence','confidenceRT'}
            c.(key{1}) = number(q,key{1});
        end
        match = plannedQuestions(arrayfun(@(p) number(p,'questionNumber')==c.questionNumber,plannedQuestions));
        assert(numel(match)==1,'LPP:Question','Saved comprehension question is absent from the plan');
        plannedOptions = reshape(cellstr(string(field(match,'options',{}))),1,[]);
        assert(strcmp(c.question,text(match,'question')) && isequal(c.options,plannedOptions) && ...
            c.correctAnswer==number(match,'correctAnswer'),'LPP:QuestionMismatch', ...
            'Question text, options, or answer key differs from the plan');
        qTimes = [c.responseTime c.RT c.confidenceRT];
        assert(all(qTimes(isfinite(qTimes))>=0),'LPP:Question','Negative comprehension response time');
        if isfinite(c.response) && isfinite(c.correctAnswer)
            assert(ismember(c.response,1:4) && ismember(c.correctAnswer,1:4), ...
                'LPP:Question','Comprehension answer outside 1 to 4');
            c.correct = c.response==c.correctAnswer;
            suppliedCorrect = number(q,'correct');
            assert(~isfinite(suppliedCorrect) || suppliedCorrect==double(c.correct), ...
                'LPP:QuestionMismatch','Saved comprehension correctness differs from answer key');
        end
        if isfinite(c.confidence)
            assert(ismember(c.confidence,1:4),'LPP:Question','Confidence outside 1 to 4');
        end
        Info.comprehension(end+1) = c;
    end
end
Info.completedProbes = sum(completed);
Info.participant = importParticipant(session);
if strcmp(text(session,'status'),'complete')
    assert(all(completed),'LPP:IncompleteFinal','Session is marked complete but some probes are incomplete');
    for k = 1:numel(plan)
        expected = asStructArray(field(plan(k),'questions',struct([])));
        answers = Info.comprehension([Info.comprehension.section]==sectionNumbers(k));
        assert(numel(answers)==numel(expected) && all(isfinite([answers.response])) && ...
            all(isfinite([answers.confidence])) && all(isfinite([answers.RT])) && ...
            all(isfinite([answers.confidenceRT])),'LPP:IncompleteFinal', ...
            'Session is marked complete but section %d has incomplete comprehension answers',sectionNumbers(k));
    end
end
Web = struct('session',session,'importedAtISO', ...
    char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")), ...
    'sourceFile',sourceFile,'trialIndex',webTrialIndex, ...
    'completedTrialMask',completed, ...
    'timestampTimezone','UTC', ...
    'labTimestampNote','Info.startTime and endTime use the lab display format but refer to UTC; original ISO timestamps remain in Web.session', ...
    'responseTimeClock','Browser performance clock in seconds, not Psychtoolbox GetSecs', ...
    'RTDefinition','Choice RT starts after previously held keys are released; recall RT starts after field focus; all durations are seconds', ...
    'probeToRecallDefinition','Scheduled audio stop to recall submit, in seconds; includes beep and all response screens', ...
    'audiobookPathNote','Info.audiobookFile retains the original-section reference as in the lab; actual numbered playback files are recorded in Web.session.plan', ...
    'recallTextNote','Info.trials.recallResponse uses strtrim as in the lab; the raw typed response remains in Web.session');
if ~isempty(find(completed,1,'last')) && ~all(completed(1:find(completed,1,'last')))
    warning('LPP:Noncontiguous','Completed trials are not contiguous; inspect Web.completedTrialMask');
end
prefix = filePrefix(session,pid);
outDir = fullfile(outputRoot,prefix);
matFile = fullfile(outDir,'logfile.mat');
if isfile(matFile)
    old = load(matFile,'Info','Web');
    sameSession = isfield(old,'Web') && isfield(old.Web,'session') && ...
        strcmp(text(old.Web.session,'session_id'),text(session,'session_id')) && ...
        ~isempty(text(session,'session_id'));
    if ~sameSession
        suffix = regexprep(text(session,'session_id'),'[^A-Za-z0-9_-]','_');
        if isempty(suffix), suffix = datestr(now,'HHMMSSFFF'); end
        suffix = suffix(max(1,end-7):end);
        outDir = fullfile(outputRoot,[prefix '_' suffix]);
        matFile = fullfile(outDir,'logfile.mat');
        assert(~isfile(matFile),'LPP:OutputExists', ...
            'Output already exists for another session; choose a different outputRoot');
    else
        prior = old.Web.session;
        assert(strcmp(text(prior,'participant_id'),pid) && ...
            strcmp(text(prior,'startISO'),text(session,'startISO')) && ...
            isequaln(getPlan(prior),plan),'LPP:ConflictingBackup', ...
            'This session ID has different participant information or a different stimulus plan');
        oldRevision = revision(prior);
        newRevision = revision(session);
        assert(isfinite(oldRevision) && isfinite(newRevision) && newRevision>=oldRevision, ...
            'LPP:OlderBackup','Backup version is older or cannot be ordered safely; choose a different outputRoot');
        assert(Info.completedProbes>=old.Info.completedProbes && ...
            numel(Info.comprehension)>=numel(old.Info.comprehension), ...
            'LPP:OlderBackup','Existing import contains more completed data');
        assertCompatibleProgress(old,Info,completed);
        if ~isequaln(old.Info,Info)
            assert(newRevision>oldRevision,'LPP:ConflictingBackup', ...
                'Two different response datasets have the same snapshot version');
        end
    end
end
if ~isfolder(outDir), mkdir(outDir); end
temporaryMat = [tempname(outDir) '.mat'];
save(temporaryMat,'Info','Web','-v7');
[ok,message] = movefile(temporaryMat,matFile,'f');
assert(ok,'LPP:SaveFailed','Could not finish saving: %s',message);
fprintf('Imported %s: %d/%d probes, %d comprehension answers\n%s\n', ...
    pid,Info.completedProbes,numel(Info.trials),numel(Info.comprehension),matFile);
end

function assertCompatibleProgress(old,Info,completed)
assert(numel(old.Info.trials)==numel(Info.trials),'LPP:ConflictingBackup','Trial plan length changed');
oldMask = false(1,numel(old.Info.trials));
if isfield(old.Web,'completedTrialMask')
    oldMask = reshape(logical(old.Web.completedTrialMask),1,[]);
else
    oldMask(1:old.Info.completedProbes) = true;
end
assert(numel(oldMask)==numel(completed) && all(completed(oldMask)), ...
    'LPP:ConflictingBackup','Previously completed trials are now missing');
for j = reshape(find(oldMask),1,[])
    assert(isequaln(old.Info.trials(j),Info.trials(j)),'LPP:ConflictingBackup', ...
        'Completed probe %d contains different answers; retain both backups in different output folders',j);
end
for j = 1:numel(old.Info.comprehension)
    prior = old.Info.comprehension(j);
    hit = find([Info.comprehension.section]==prior.section & ...
        [Info.comprehension.questionNumber]==prior.questionNumber);
    assert(numel(hit)==1,'LPP:ConflictingBackup','A previous comprehension answer is missing');
    next = Info.comprehension(hit);
    keys = fieldnames(prior);
    for k = 1:numel(keys)
        a = prior.(keys{k}); b = next.(keys{k});
        if isnumeric(a) && isscalar(a) && isnan(a), continue; end
        assert(isequaln(a,b),'LPP:ConflictingBackup','A previously saved comprehension answer changed');
    end
end
names = fieldnames(old.Info.participant);
for j = 1:numel(names)
    prior = old.Info.participant.(names{j});
    if isfinite(prior.response)
        assert(isequaln(prior,Info.participant.(names{j})),'LPP:ConflictingBackup', ...
            'A previously saved demographic answer changed');
    end
end
end

function value = revision(s)
value = number(s,'snapshot_version');
if ~isfinite(value), value = number(s,'revision'); end
end

function plan = getPlan(s)
if isfield(s,'plan'), plan = asStructArray(s.plan);
elseif isfield(s,'meta') && isfield(s.meta,'plan'), plan = asStructArray(s.meta.plan);
else
    error('LPP:MissingPlan',['Backup has no complete section plan, so unstarted trials cannot be reconstructed ' ...
        'without guessing; export a full typed-study backup']);
end
assert(~isempty(plan) && all(isfield(plan,{'section','audiobookFile','probes'})), ...
    'LPP:Plan','Incomplete section plan');
end

function participant = importParticipant(s)
names = {'sokaStudent','nativeEnglish','englishProficiency', ...
    'priorExposureLittlePrince','familiarityLittlePrince'};
questions = {'Are you a student at Soka University of America?', ...
    'Is English your native language (i.e., a language you learned from birth or during early childhood)?', ...
    'How would you rate your English proficiency?', ...
    'Before today, how much of The Little Prince had you read or listened to?', ...
    'Before today, how familiar were you with the story of The Little Prince?'};
options = {{'Yes','No'},{'Yes','No'}, ...
    {'Beginner','Intermediate','Advanced','Near-native','Native'}, ...
    {'None of it','Some of it','All of it'}, ...
    {'Not at all familiar','Slightly familiar','Moderately familiar','Very familiar'}};
source = field(s,'participant',struct());
participant = struct();
for k = 1:numel(names)
    answer = field(source,names{k},struct());
    chosen = number(answer,'response');
    responseText = "";
    if isfinite(chosen)
        assert(ismember(chosen,1:numel(options{k})),'LPP:Participant','Invalid demographic answer');
        responseText = string(options{k}{chosen});
        supplied = text(answer,'responseText');
        assert(isempty(supplied) || strcmp(supplied,char(responseText)), ...
            'LPP:Participant','Demographic option number and text disagree');
    end
    participant.(names{k}) = struct('question',questions{k},'options',{options{k}}, ...
        'response',chosen,'responseText',responseText,'RT',number(answer,'RT'));
end
end

function validateTrial(t,done)
if isfinite(t.onTask), assert(ismember(t.onTask,[0 1]),'LPP:Trial','onTask must be 0 or 1'); end
if isfinite(t.KSS), assert(ismember(t.KSS,1:9),'LPP:Trial','KSS must be 1 to 9'); end
rts = [t.onTaskRT t.KSSRT t.recallRT];
assert(all(rts(isfinite(rts))>=0),'LPP:Trial','Negative response time');
if done
    assert(all(isfinite([t.onTask t.KSS rts])),'LPP:Trial','Complete trial has missing responses or timing');
end
end

function value = field(s,name,fallback)
if isstruct(s) && isscalar(s) && isfield(s,name), value = s.(name);
else, value = fallback; end
end

function value = number(s,name)
value = field(s,name,NaN);
if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ~isfinite(value), value = NaN;
else, value = double(value); end
end

function value = text(s,name,fallback)
if nargin<3, fallback = ''; end
value = field(s,name,fallback);
if isempty(value), value = fallback; end
assert(ischar(value) || (isstring(value) && isscalar(value)), ...
    'LPP:Text','Expected a text value for %s',name);
value = char(value);
end

function records = asStructArray(value)
if isempty(value), records = struct([]); return; end
if iscell(value)
    names = {};
    for k = 1:numel(value)
        assert(isstruct(value{k}) && isscalar(value{k}),'LPP:Array','Expected record objects');
        names = union(names,fieldnames(value{k}),'stable');
    end
    template = cell2struct(repmat({[]},numel(names),1),names,1);
    normalized = repmat(template,1,numel(value));
    for k = 1:numel(value)
        keys = fieldnames(value{k});
        for j = 1:numel(keys), normalized(k).(keys{j}) = value{k}.(keys{j}); end
    end
    value = normalized;
end
assert(isstruct(value),'LPP:Array','Expected an array of records');
records = reshape(value,1,[]);
end

function value = labTime(iso)
if isempty(iso), value = ''; return; end
try
    dt = datetime(iso,'InputFormat',"yyyy-MM-dd'T'HH:mm:ss.SSSXXX",'TimeZone','UTC','Locale','en_US');
catch
    try
        dt = datetime(iso,'InputFormat',"yyyy-MM-dd'T'HH:mm:ssXXX",'TimeZone','UTC','Locale','en_US');
    catch
        error('LPP:Time','Unrecognized UTC timestamp: %s',iso);
    end
end
dt.Format = 'dd-MMM-yyyy HH:mm:ss';
value = char(dt);
end

function prefix = filePrefix(s,pid)
prefix = text(s,'file_prefix');
if ~isempty(prefix) && ~isempty(regexp(prefix,'^[A-Za-z0-9_-]{1,110}$','once')), return; end
iso = text(s,'startISO',text(s,'createdISO'));
if numel(iso)>=19
    stamp = regexprep(iso(1:19),'[-:]','');
    stamp(9) = '_';
else
    stamp = datestr(now,'yyyymmdd_HHMMSS');
end
prefix = [pid '_' stamp];
end
