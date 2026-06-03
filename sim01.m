function [costs, sumq95, q95svr] = sim01(exp_cfg, strategy)
% SIM01  仿真引擎：原始数据生成 + 启发式策略 + Q95成本计算 + 仿真主循环
%
%   输入: exp_cfg  包含字段:
%           .M, .Days, .SlotDur, .QPct, .Seed, .Rounds, .Cap, .Price
%         strategy  策略名 ('cheapest','ld_bal','wl_bal','dsplit','full','qburst')
%
%   输出: costs   [1×Rounds] 每轮总成本
%         sumq95  [1×Rounds] 每轮总Q95
%         q95svr  [M×Rounds] 每轮每服务器Q95
%
%   架构: ①原始数据生成 → ②策略定义 → ③Q95/成本 → ④仿真主循环

%% ═══════════════════ ① 原始数据生成 ═══════════════════
    function DATA = generate_data()
        M = exp_cfg.M;  T = 8640;  R = exp_cfg.Rounds;
        DATA = cell(R, T);
        for r = 1:R
            ds = RandStream('mt19937ar','Seed', exp_cfg.Seed + r - 1);
            gs = RandStream.getGlobalStream();
            RandStream.setGlobalStream(ds);
            for slot = 1:T
                day_slot = mod(slot-1, 288) + 1;  lbl = 2;
                peak = [64,65,89,93,100:108,110,112:116,118:138,140,141,145,147:150,153:155,157,158,160,162,163,165:167,169,170,172:175,177,178,181:183];
                low  = [198:200,202:212,214:224,226:264];
                if ismember(day_slot, low), lbl = 1;
                elseif ismember(day_slot, peak), lbl = 3; end
                lambda = [73.85; 77.60; 82.63];  lambda = lambda(lbl);
                rate = lambda / exp_cfg.SlotDur;
                mx = max(ceil(lambda * 4), 10);
                inter = exprnd(1/rate, mx, 1);
                ct = cumsum(inter);  ct(ct >= exp_cfg.SlotDur) = [];
                n = length(ct);  dem = zeros(n, 1);
                for i = 1:n
                    if rand() < 0.4094
                        d = 110.75 + 54.85 * randn();
                    else
                        d = 1014.25 + 78.75 * randn();
                    end
                    dem(i) = max(46, min(1460, round(d)));
                end
                DATA{r, slot} = struct('times', ct, 'demands', dem);
            end
            RandStream.setGlobalStream(gs);
        end
    end

%% ═══════════════════ ② 启发式策略 ═══════════════════
    function c = apply_strategy(candidates, H, slot, d_k)
        c = -1;
        switch strategy
            case 'cheapest'
                pp = prc(candidates);  [~, mi] = min(pp);
                tie = candidates(pp == pp(mi));
                c = tie(randi(length(tie)));

            case 'ld_bal'
                ld = H(candidates, slot);  [~, mi] = min(ld);
                tie = candidates(ld == ld(mi));
                c = tie(randi(length(tie)));

            case 'wl_bal'
                wl = wl_acc(candidates);  [~, mi] = min(wl);
                tie = candidates(wl == wl(mi));
                c = tie(randi(length(tie)));

            case 'dsplit'
                if d_k <= 1000
                    for try_i = 1:M
                        svr = mod(rr_ptr + try_i - 2, M) + 1;
                        if ismember(svr, candidates)
                            c = svr;  rr_ptr = mod(svr, M) + 1;  return;
                        end
                    end
                    c = rand_pick(candidates);
                else
                    wl = wl_acc(candidates);  [~, mi] = min(wl);
                    tie = candidates(wl == wl(mi));
                    c = rand_pick(tie);
                end

            case 'full'
                scores = zeros(length(candidates), 1);
                for ci = 1:length(candidates)
                    svr = candidates(ci);
                    rem  = cap(svr) - H(svr, slot);
                    free = 1 - H(svr, slot) / cap(svr);
                    scores(ci) = prc(svr) * d_k / max(1, rem * free);
                end
                [~, mi] = min(scores);
                tie = candidates(scores == scores(mi));
                c = rand_pick(tie);

            case 'qburst'
                P_line = 62500 * cap / sum(cap);
                if any(H(candidates, slot) > P_line(candidates))
                    cand_q = candidates(burst_q(candidates) > 0);
                    if isempty(cand_q)
                        burst_q(:) = 432;  cand_q = candidates;
                    end
                    pp = prc(cand_q);  [~, mi] = min(pp);
                    tie = cand_q(pp == pp(mi));
                    c = rand_pick(tie);
                else
                    ratios = H(candidates, slot) ./ P_line(candidates);
                    [~, mi] = min(ratios);
                    tie = candidates(ratios == ratios(mi));
                    c = rand_pick(tie);
                end
        end
    end

    function c = rand_pick(cand)
        if isempty(cand), c = -1; else, c = cand(randi(length(cand))); end
    end

%% ═══════════════════ ③ Q95 与成本计算 ═══════════════════
    function q = q95(vec)
        n = length(vec);
        discard = ceil(n * (100 - exp_cfg.QPct) / 100);
        s = sort(vec, 'ascend');
        q = s(max(1, n - discard));
    end

%% ═══════════════════ ④ 仿真主循环 ═══════════════════
    M   = exp_cfg.M;
    cap = exp_cfg.Cap(:)';
    prc = exp_cfg.Price(:)';
    ROUNDS = exp_cfg.Rounds;

    DATA = generate_data();
    T = size(DATA, 2);

    costs  = zeros(1, ROUNDS);
    sumq95 = zeros(1, ROUNDS);
    q95svr = zeros(M, ROUNDS);

    for r = 1:ROUNDS
        H = zeros(M, T);
        wl_acc = zeros(M, 1);
        rr_ptr = 1;
        burst_q = ones(M, 1) * 432;

        for slot = 1:T
            wl_acc(:) = 0;
            demands = DATA{r, slot}.demands;
            if isempty(demands), continue; end

            for ri = 1:length(demands)
                d_k = demands(ri);
                candidates = find(H(:, slot) < cap);
                if isempty(candidates)
                    [~, fb] = min(H(:, slot));
                    H(fb, slot) = H(fb, slot) + d_k;
                    continue;
                end

                c = apply_strategy(candidates, H, slot, d_k);
                if c > 0 && H(c, slot) + d_k <= cap(c)
                    H(c, slot) = H(c, slot) + d_k;
                    wl_acc(c) = wl_acc(c) + prc(c) * d_k;
                else
                    [~, fb] = min(H(:, slot));
                    H(fb, slot) = H(fb, slot) + d_k;
                    wl_acc(fb) = wl_acc(fb) + prc(fb) * d_k;
                end
            end

            % qburst: 时间片结束更新免费配额
            if strcmp(strategy, 'qburst')
                P_line = 62500 * cap / sum(cap);
                for svr = 1:M
                    if H(svr, slot) > P_line(svr)
                        burst_q(svr) = burst_q(svr) - 1;
                    end
                end
            end
        end

        q95_s = zeros(M, 1);
        for s = 1:M
            q95_s(s) = q95(H(s, :));
        end
        costs(r)  = sum(prc .* q95_s');
        sumq95(r) = sum(q95_s);
        q95svr(:, r) = q95_s;
    end
end
