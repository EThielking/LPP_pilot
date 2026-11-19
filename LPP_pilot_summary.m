function [Summary, Trials, figureFile] = LPP_pilot_summary(inputFile, outputDir)
% Make a one-page pilot report from one imported logfile.mat
% Run LPP_pilot_summary with no arguments to choose the participant file
% You may also select a typed web JSON backup to import and summarize it
% Recall scoring ignores case and punctuation but does not forgive misspellings
% All raw responses are retained in the trial CSV for manual review

if nargin<1 || isempty(inputFile)
    [name,folder] = uigetfile({'*.mat;*.json','LPP logfile or web backup'}, ...
        'Select one participant');
    if isequal(name,0), Summary = table(); Trials = table(); figureFile = ''; return; end
    inputFile = fullfile(folder,name);
end
inputFile = char(string(inputFile));
[folder,~,extension] = fileparts(inputFile);
if strcmpi(extension,'.json')
    [~,inputFile] = LPP_import_web(inputFile);
    folder = fileparts(inputFile);
end
loaded = load(inputFile,'Info','Web');
assert(isfield(loaded,'Info'),'LPP:MissingInfo','The MAT file must contain Info');
Info = loaded.Info;
assert(isfield(Info,'trials') && isfield(Info.trials,'recallResponse'), ...
    'LPP:Protocol','This summary requires the typed-recall Info structure');
if nargin<2 || isempty(outputDir), outputDir = fullfile(folder,'pilot_summary'); end
outputDir = char(string(outputDir));
if ~isfolder(outputDir), mkdir(outputDir); end

n = numel(Info.trials);
completed = false(n,1);
completed(1:min(n,double(Info.completedProbes))) = true;
total = nan(n,1);
status = "lab_file";
if isfield(loaded,'Web')
    Web = loaded.Web;
    if isfield(Web,'completedTrialMask') && numel(Web.completedTrialMask)==n
        completed = logical(Web.completedTrialMask(:));
    end
    if isfield(Web,'trialIndex') && numel(Web.trialIndex)==n
        total = reshape([Web.trialIndex.probeToRecallEnd_sec],[],1);
    end
    if isfield(Web,'session') && isfield(Web.session,'status'), status = string(Web.session.status); end
end
probe = zeros(n,1); section = zeros(n,1); onTask = nan(n,1); KSS = nan(n,1);
recallRT = nan(n,1); onTaskRT = nan(n,1); KSSRT = nan(n,1);
response = strings(n,1); target = strings(n,1); cue = strings(n,1);
exact = nan(n,1); fraction = nan(n,1); matched = nan(n,1); targetCount = nan(n,1);
for j = 1:n
    t = Info.trials(j);
    probe(j) = t.probeNumber; section(j) = t.section;
    onTask(j) = t.onTask; KSS(j) = t.KSS;
    recallRT(j) = t.recallRT; onTaskRT(j) = t.onTaskRT; KSSRT(j) = t.KSSRT;
    response(j) = string(t.recallResponse); target(j) = string(t.recallTarget); cue(j) = string(t.cue);
    if completed(j)
        [rWords,rText] = normalizeWords(response(j));
        [tWords,tText] = normalizeWords(target(j));
        if ~isempty(tWords)
            exact(j) = double(strcmp(rText,tText));
            matched(j) = longestSubsequence(rWords,tWords);
            targetCount(j) = numel(tWords);
            fraction(j) = matched(j)/targetCount(j);
        end
    end
end
attention = repmat("Missing",n,1);
attention(onTask==1) = "On-task";
attention(onTask==0) = "Off-task";
Trials = table(probe,section,completed,attention,onTask,KSS,cue,target,response, ...
    exact,fraction,matched,targetCount,onTaskRT,KSSRT,recallRT,total, ...
    'VariableNames',{'Probe','Section','Completed','Attention','OnTask','KSS','Cue', ...
    'RecallTarget','RecallResponse','ExactRecall','OrderedWordFraction','MatchedWords', ...
    'TargetWordCount','OnTaskRT_sec','KSSRT_sec','RecallRT_sec','ProbeToRecallEnd_sec'});
OT = completed & onTask==1;
OFF = completed & onTask==0;
scorable = completed & isfinite(exact);
qCorrect = zeros(0,1); qConfidence = zeros(0,1);
for j = 1:numel(Info.comprehension)
    q = Info.comprehension(j);
    if isfinite(q.response) && isfinite(q.correctAnswer)
        qCorrect(end+1,1) = double(q.response==q.correctAnswer);
        qConfidence(end+1,1) = q.confidence;
    end
end
pid = string(Info.subjectID);
Summary = table(pid,status,n,sum(completed),sum(scorable),sum(OT),sum(OFF), ...
    100*average(onTask(completed)),100*average(exact(scorable)), ...
    100*average(fraction(scorable)),100*average(exact(OT)),100*average(exact(OFF)), ...
    100*average(fraction(OT)),100*average(fraction(OFF)), ...
    average(KSS(completed)),average(KSS(OT)),average(KSS(OFF)), ...
    average(total(completed)),middle(total(completed)),middle(total(OT)),middle(total(OFF)), ...
    sum(isfinite(total(OT))),sum(isfinite(total(OFF))),average(recallRT(completed)), ...
    numel(qCorrect),100*average(qCorrect),average(qConfidence), ...
    'VariableNames',{'SubjectID','Status','PlannedProbes','CompletedProbes','ScorableRecallN', ...
    'OnTaskN','OffTaskN','OnTaskPct','ExactRecallPct','OrderedWordPct', ...
    'ExactRecallOnTaskPct','ExactRecallOffTaskPct','OrderedWordOnTaskPct','OrderedWordOffTaskPct', ...
    'MeanKSS','MeanKSSOnTask','MeanKSSOffTask','MeanProbeToRecall_sec', ...
    'MedianProbeToRecall_sec','MedianProbeToRecallOnTask_sec','MedianProbeToRecallOffTask_sec', ...
    'ProbeToRecallOnTaskN','ProbeToRecallOffTaskN','MeanRecallRT_sec', ...
    'ComprehensionAnsweredN','ComprehensionCorrectPct','MeanConfidence'});

safeID = regexprep(char(pid),'[^A-Za-z0-9_-]','_');
base = fullfile(outputDir,[safeID '_pilot_summary']);
figureFile = [base '.png'];
writetable(csvLiteralTable(Trials),fullfile(outputDir,[safeID '_trials.csv']));
writetable(csvLiteralTable(Summary),[base '.csv']);

ink = [0.16 0.20 0.26]; muted = [0.43 0.48 0.53];
green = [0.20 0.51 0.43]; coral = [0.76 0.39 0.29]; blue = [0.31 0.40 0.61];
fig = figure('Color',[0.985 0.983 0.972],'Position',[60 60 1260 880], ...
    'Name',[char(pid) ' | LPP pilot summary'],'NumberTitle','off');
layout = tiledlayout(fig,3,2,'Padding','compact','TileSpacing','compact');
title(layout,sprintf('%s  |  LPP pilot summary',char(pid)), ...
    'FontName','Helvetica','FontSize',23,'FontWeight','normal','Color',ink,'Interpreter','none');
subtitle(layout,sprintf(['%d / %d probes completed  |  On-task %d  |  Off-task %d  |  ' ...
    'Comprehension %s (%d answers)  |  %s'],sum(completed),n,sum(OT),sum(OFF), ...
    percentLabel(100*average(qCorrect)),numel(qCorrect),char(status)), ...
    'FontName','Helvetica','FontSize',11,'Color',muted,'Interpreter','none');

ax = nexttile(layout,[1 2]); hold(ax,'on');
scatter(ax,probe(OT),100*fraction(OT),48,green,'filled','DisplayName','On-task');
scatter(ax,probe(OFF),100*fraction(OFF),48,coral,'filled','DisplayName','Off-task');
missingState = scorable & ~OT & ~OFF;
if any(missingState), scatter(ax,probe(missingState),100*fraction(missingState),48,muted,'filled','DisplayName','Missing attention'); end
for boundary = reshape(find(diff(section)~=0),1,[])
    xline(ax,boundary+.5,':','Color',[.75 .77 .78],'HandleVisibility','off');
end
ylim(ax,[-7 107]); xlim(ax,[.4 max(1,n)+.6]); yticks(ax,[0 25 50 75 100]);
xlabel(ax,'Probe in story order'); ylabel(ax,'Ordered words recalled (%)');
title(ax,'Recall across the session','FontWeight','normal');
legend(ax,'Location','eastoutside','Box','off'); styleAxes(ax,ink);

ax = nexttile(layout); hold(ax,'on');
values = 100*[average(exact(OT)) average(fraction(OT)); average(exact(OFF)) average(fraction(OFF))];
bars = bar(ax,values,'grouped'); bars(1).FaceColor = blue; bars(2).FaceColor = green;
xticks(ax,[1 2]); xticklabels(ax,{sprintf('On-task (n=%d)',sum(isfinite(exact(OT)))), ...
    sprintf('Off-task (n=%d)',sum(isfinite(exact(OFF))))}); ylim(ax,[0 112]); yticks(ax,[0 25 50 75 100]);
ylabel(ax,'Recall accuracy (%)'); title(ax,'Recall by attentional state','FontWeight','normal');
legend(ax,{'Entire response exact','Ordered-word fraction'},'Location','southoutside', ...
    'Orientation','horizontal','Box','off','FontSize',9);
if ~any(isfinite(values(:))), text(ax,1.5,50,'No completed recall responses','HorizontalAlignment','center','Color',muted); end
styleAxes(ax,ink);

ax = nexttile(layout); hold(ax,'on');
plot(ax,probe(completed),KSS(completed),'-','Color',[.75 .78 .80],'HandleVisibility','off');
scatter(ax,probe(OT),KSS(OT),27,green,'filled');
scatter(ax,probe(OFF),KSS(OFF),27,coral,'filled');
xlim(ax,[.4 max(1,n)+.6]); ylim(ax,[.5 9.5]); yticks(ax,1:9);
xlabel(ax,'Probe'); ylabel(ax,'Sleepiness (1–9)'); title(ax,'Sleepiness across the session','FontWeight','normal');
styleAxes(ax,ink);

ax = nexttile(layout); hold(ax,'on');
colors = [green;coral]; masks = {OT,OFF};
for k = 1:2
    vals = total(masks{k} & isfinite(total));
    if isempty(vals), continue; end
    if numel(vals)==1, offsets = 0; else, offsets = linspace(-.13,.13,numel(vals))'; end
    scatter(ax,k+offsets,vals,24,colors(k,:),'filled','MarkerFaceAlpha',.6);
    plot(ax,[k-.23 k+.23],[median(vals) median(vals)],'-','Color',ink,'LineWidth',2);
end
xticks(ax,[1 2]); xticklabels(ax,{sprintf('On-task (n=%d)',sum(isfinite(total(OT)))), ...
    sprintf('Off-task (n=%d)',sum(isfinite(total(OFF))))}); xlim(ax,[.5 2.5]);
ylabel(ax,'Seconds'); title(ax,'Probe pause → recall submitted','FontWeight','normal');
if ~any(isfinite(total(completed)))
    ylim(ax,[0 1]); text(ax,1.5,.5,{'Total timing unavailable','Stage RTs remain in the CSV'}, ...
        'HorizontalAlignment','center','Color',muted,'FontSize',10);
else
    ymax = max(total(completed & isfinite(total)));
    ylim(ax,[0 max(1,ymax*1.12)]);
end
styleAxes(ax,ink);

ax = nexttile(layout); axis(ax,'off');
description = { ...
    sprintf('Overall exact recall: %s  |  Ordered words: %s', ...
        percentLabel(Summary.ExactRecallPct),percentLabel(Summary.OrderedWordPct)), ...
    sprintf('Recall typing time: %s s average',numberLabel(Summary.MeanRecallRT_sec)), ...
    sprintf('Total pause: %s s median',numberLabel(Summary.MedianProbeToRecall_sec)), ...
    '', ...
    'Exact recall requires the full normalized response to match the target', ...
    'Ordered-word fraction = matching target words in order / target words', ...
    'Case and punctuation are normalized; spelling and substitutions matter', ...
    'Hyphens/underscores split words; contraction expansions are not inferred', ...
    'Extra words reduce exact recall but do not reduce the ordered-word fraction', ...
    'Incomplete trials are excluded; missing groups remain unestimated', ...
    'Timing marks are browser estimates, including beep and response transitions', ...
    'Dots are individual probes; horizontal lines show median response time', ...
    'Review raw target/response pairs in the trial CSV before interpreting scores'};
text(ax,0,1,description,'Units','normalized','VerticalAlignment','top','Interpreter','none', ...
    'FontName','Helvetica','FontSize',10,'Color',muted);

drawnow;
exportgraphics(fig,figureFile,'Resolution',180,'BackgroundColor',fig.Color);
exportgraphics(fig,[base '.pdf'],'ContentType','vector','BackgroundColor',fig.Color);
fprintf('Saved pilot figure and CSV tables:\n%s\n',figureFile);
disp(Summary);
end

function [words,normalized] = normalizeWords(value)
normalized = lower(char(string(value)));
normalized = strrep(normalized,'''','');
normalized = strrep(normalized,char(8216),'');
normalized = strrep(normalized,char(8217),'');
normalized = regexprep(normalized,'[-_]',' ');
normalized(~isstrprop(normalized,'alphanum') & ~isspace(normalized)) = ' ';
normalized = strtrim(regexprep(normalized,'\s+',' '));
if isempty(normalized), words = {}; else, words = strsplit(normalized,' '); end
end

function n = longestSubsequence(a,b)
previous = zeros(1,numel(b)+1);
for i = 1:numel(a)
    current = zeros(1,numel(b)+1);
    for j = 1:numel(b)
        if strcmp(a{i},b{j}), current(j+1) = previous(j)+1;
        else, current(j+1) = max(previous(j+1),current(j)); end
    end
    previous = current;
end
n = previous(end);
end

function value = average(values)
values = values(isfinite(values));
if isempty(values), value = NaN; else, value = mean(values); end
end

function value = middle(values)
values = values(isfinite(values));
if isempty(values), value = NaN; else, value = median(values); end
end

function value = percentLabel(number)
if isfinite(number), value = sprintf('%.1f%%',number); else, value = 'not available'; end
end

function value = numberLabel(number)
if isfinite(number), value = sprintf('%.1f',number); else, value = 'not available'; end
end

function styleAxes(ax,ink)
set(ax,'FontName','Helvetica','FontSize',10,'Color','none','XColor',ink,'YColor',ink, ...
    'Box','off','TickDir','out','YGrid','on','GridAlpha',.12,'Layer','top');
end

function exported = csvLiteralTable(original)
% Escape formula-like CSV text only, keeping returned tables and MAT data raw
% A leading apostrophe asks spreadsheet software to display a literal value
exported = original;
names = exported.Properties.VariableNames;
for column = 1:numel(names)
    values = exported.(names{column});
    if ~(isstring(values) || iscellstr(values)), continue; end
    values = string(values);
    for row = 1:numel(values)
        if ismissing(values(row)), continue; end
        raw = char(values(row));
        if isempty(raw), continue; end
        first = find(~(isspace(raw) | double(raw)<=31 | double(raw)==127),1);
        formulaLike = ~isempty(first) && any(raw(first)=='=+-@');
        leadingControl = any(double(raw(1))==[9 10 13]);
        if formulaLike || leadingControl, values(row) = "'" + values(row); end
    end
    exported.(names{column}) = values;
end
end
