%% ==================== 实验编排层 ====================
%  定义实验环境 → 调用 sim01 → 汇总输出 Excel
clear; clc;

%% ── 策略开关 (1=运行, 0=跳过) ──
SW.cheapest = 1;  SW.ld_bal = 1;  SW.wl_bal = 1;
SW.dsplit   = 1;  SW.full   = 1;  SW.qburst = 1;

STRATEGIES = fieldnames(SW);
active = {}; for i = 1:length(STRATEGIES)
    if SW.(STRATEGIES{i}), active{end+1} = STRATEGIES{i}; end
end
nS = length(active);
fprintf('>>> 激活策略 (%d/%d): %s\n', nS, length(STRATEGIES), strjoin(active, ', '));

%% ── 实验环境定义函数 ──
function cfg = env(id, desc, cap, price)
    cfg = struct('id', id, 'desc', desc, ...
        'M', 5, 'Days', 30, 'SlotDur', 300, 'QPct', 95, ...
        'Seed', 42, 'Rounds', 20, 'Cap', cap(:), 'Price', price(:));
end

%% ═══════════════ 实验环境池 ═══════════════
%  --- 无价差 (1-5) ---
E{ 1} = env('1', '90k×5, 无价差',      repmat(90000,5,1), [1.00;1.00;1.00;1.00;1.00]);
E{ 2} = env('2', '32k×5, 无价差',      repmat(32000,5,1), [1.00;1.00;1.00;1.00;1.00]);
E{ 3} = env('3', '32k→38k, 无价差',    [32000;32000;33000;35000;38000], [1.00;1.00;1.00;1.00;1.00]);
E{ 4} = env('4', '19k×5, 无价差',      repmat(19000,5,1), [1.00;1.00;1.00;1.00;1.00]);
E{ 5} = env('5', '12k→24k, 无价差',    [12000;17000;20000;22000;24000], [1.00;1.00;1.00;1.00;1.00]);

%  --- step 0.01 (6-10) ---
E{ 6} = env('6', '90k×5, 1.00→1.04',   repmat(90000,5,1), [1.00;1.01;1.02;1.03;1.04]);
E{ 7} = env('7', '32k×5, 1.00→1.04',   repmat(32000,5,1), [1.00;1.01;1.02;1.03;1.04]);
E{ 8} = env('8', '32k→38k, 1.00→1.04', [32000;32000;33000;35000;38000], [1.00;1.01;1.02;1.03;1.04]);
E{ 9} = env('9', '19k×5, 1.00→1.04',   repmat(19000,5,1), [1.00;1.01;1.02;1.03;1.04]);
E{10} = env('10','12k→24k, 1.00→1.04', [12000;17000;20000;22000;24000], [1.00;1.01;1.02;1.03;1.04]);

%  --- step 0.02 (11-15) ---
E{11} = env('11','90k×5, 1.00→1.08',   repmat(90000,5,1), [1.00;1.02;1.04;1.06;1.08]);
E{12} = env('12','32k×5, 1.00→1.08',   repmat(32000,5,1), [1.00;1.02;1.04;1.06;1.08]);
E{13} = env('13','32k→38k, 1.00→1.08', [32000;32000;33000;35000;38000], [1.00;1.02;1.04;1.06;1.08]);
E{14} = env('14','19k×5, 1.00→1.08',   repmat(19000,5,1), [1.00;1.02;1.04;1.06;1.08]);
E{15} = env('15','12k→24k, 1.00→1.08', [12000;17000;20000;22000;24000], [1.00;1.02;1.04;1.06;1.08]);

%  --- step 0.05 (16-20) ---
E{16} = env('16','90k×5, 1.00→1.20',   repmat(90000,5,1), [1.00;1.05;1.10;1.15;1.20]);
E{17} = env('17','32k×5, 1.00→1.20',   repmat(32000,5,1), [1.00;1.05;1.10;1.15;1.20]);
E{18} = env('18','32k→38k, 1.00→1.20', [32000;32000;33000;35000;38000], [1.00;1.05;1.10;1.15;1.20]);
E{19} = env('19','19k×5, 1.00→1.20',   repmat(19000,5,1), [1.00;1.05;1.10;1.15;1.20]);
E{20} = env('20','12k→24k, 1.00→1.20', [12000;17000;20000;22000;24000], [1.00;1.05;1.10;1.15;1.20]);

%  --- step 0.10 (21-25) ---
E{21} = env('21','90k×5, 1.00→1.40',   repmat(90000,5,1), [1.00;1.10;1.20;1.30;1.40]);
E{22} = env('22','32k×5, 1.00→1.40',   repmat(32000,5,1), [1.00;1.10;1.20;1.30;1.40]);
E{23} = env('23','32k→38k, 1.00→1.40', [32000;32000;33000;35000;38000], [1.00;1.10;1.20;1.30;1.40]);
E{24} = env('24','19k×5, 1.00→1.40',   repmat(19000,5,1), [1.00;1.10;1.20;1.30;1.40]);
E{25} = env('25','12k→24k, 1.00→1.40', [12000;17000;20000;22000;24000], [1.00;1.10;1.20;1.30;1.40]);

nExp = length(E);
M = 5;
fprintf('>>> %d 个实验环境已定义\n', nExp);

%% ═══════════════ 主循环: 调用 sim01 ═══════════════
fprintf('>>> 开始仿真 (%d环境 × %d策略)\n\n', nExp, nS);
ALL = struct();

for e = 1:nExp
    exp = E{e};
    fprintf('[%s] %s\n', exp.id, exp.desc);

    costs  = zeros(nS, exp.Rounds);
    sumq95 = zeros(nS, exp.Rounds);
    q95svr = zeros(M, nS, exp.Rounds);
    elaps  = zeros(1, nS);

    for si = 1:nS
        t0 = tic;
        [costs(si,:), sumq95(si,:), q95svr(:,si,:)] = sim01(exp, active{si});
        elaps(si) = toc(t0);
    end

    mc = mean(costs, 2);  [bc, bi] = min(mc);
    fprintf('  → 最优: %s (%.0f) | ', upper(active{bi}), bc);
    for si = 1:nS, fprintf('%s=%.0f ', active{si}, mc(si)); end
    fprintf('\n\n');

    ALL(e).id = exp.id;   ALL(e).desc = exp.desc;
    ALL(e).costs = costs; ALL(e).sumq95 = sumq95;
    ALL(e).q95svr = q95svr; ALL(e).elaps = elaps;
    ALL(e).best_idx = bi;  ALL(e).cap = exp.Cap;
    ALL(e).price = exp.Price;
end

%% ═══════════════ 输出 Excel ═══════════════
fprintf('>>> 生成 Excel...\n');
outfile = 'results/sim_results.xlsx';

% -- Sheet 1: 20轮统计 --
T1_cell = {};
for e = 1:nExp
    r = ALL(e);
    mc = mean(r.costs,2);  sc = std(r.costs,0,2);
    mq = mean(r.sumq95,2); [bc, bi] = min(mc);
    row = {r.id, r.desc, upper(active{bi}), bc};
    for si = 1:nS
        gap = (mc(si)-bc)/bc*100;
        row = [row, {gap, mc(si), sc(si), mq(si)}];
    end
    T1_cell = [T1_cell; row];
end
v1 = {'编号','场景','最优策略','最优平均成本'};
for i = 1:nS
    v1 = [v1, {[active{i} '_gap%'],[active{i} '_成本'],[active{i} '_std'],[active{i} '_Q95']}];
end
writetable(cell2table(T1_cell,'VariableNames',v1), outfile, 'Sheet','20轮统计');

% -- Sheet 2: 第20轮实时 --
T2_cell = {};  last_r = exp.Rounds;
for e = 1:nExp
    r = ALL(e);  cap = r.cap;
    lc = r.costs(:,end);  [bc, bi] = min(lc);
    for si = 1:nS
        gap = (lc(si)-bc)/bc*100;
        qv = r.q95svr(:,si,last_r);
        row = {r.id, r.desc, active{si}, lc(si), gap, sum(qv)};
        for s = 1:5
            rt = qv(s)/cap(s)*100;
            row = [row, {sprintf('%.0f(%.1f%%)', qv(s), rt)}];
        end
        row = [row, {double(si==bi)}];
        T2_cell = [T2_cell; row];
    end
end
v2 = {'编号','场景','策略','成本','gap%','总Q95'};
for s = 1:5, v2 = [v2, {sprintf('S%d_Q95(负载率)',s)}]; end
v2 = [v2, {'是否最优'}];
writetable(cell2table(T2_cell,'VariableNames',v2), outfile, 'Sheet','第20轮实时');

% -- 格式化 --
fprintf('>>> 格式化...\n');
try
    Excel = actxserver('Excel.Application');
    Excel.Visible = false;
    WB = Excel.Workbooks.Open(fullfile(pwd, outfile));
    s1 = WB.Sheets.Item('20轮统计');  lr = s1.UsedRange.Rows.Count;
    for row = 2:lr
        bs = strtrim(s1.Cells(row,3).Value);
        if isempty(bs), continue; end
        s1.Cells(row,3).Font.Bold = true;  s1.Cells(row,4).Font.Bold = true;
        for i = 1:nS
            if strcmpi(bs, active{i})
                c0 = 4+(i-1)*4+1;
                for c2 = 0:3, s1.Cells(row,c0+c2).Font.Bold = true; end; break;
            end
        end
        s1.Cells(row,4).NumberFormat = '#,##0';
        for i = 1:nS
            c0 = 4+(i-1)*4+1;
            s1.Cells(row,c0).NumberFormat   = '0.0"%"';
            s1.Cells(row,c0+1).NumberFormat = '#,##0';
            s1.Cells(row,c0+2).NumberFormat = '#,##0.0';
            s1.Cells(row,c0+3).NumberFormat = '#,##0';
        end
    end
    s2 = WB.Sheets.Item('第20轮实时');
    lr2 = s2.UsedRange.Rows.Count;  lc2 = s2.UsedRange.Columns.Count;
    for row = 2:lr2
        if s2.Cells(row,lc2).Value == 1
            for c = 1:lc2-1, s2.Cells(row,c).Font.Bold = true; end
        end
        s2.Cells(row,4).NumberFormat = '#,##0';
        s2.Cells(row,5).NumberFormat = '0.0"%"';
        s2.Cells(row,6).NumberFormat = '#,##0';
    end
    WB.Save();  WB.Close();  Excel.Quit();
    fprintf('>>> 格式化完成\n');
catch
    fprintf('>>> 格式化跳过\n');
end

fprintf('>>> 已保存: %s\n', outfile);
fprintf('==================== 完成 ====================\n');
