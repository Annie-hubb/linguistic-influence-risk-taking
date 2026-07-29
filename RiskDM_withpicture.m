% =========================================================================
% 风险决策自适应任务 (Gain Framework) - 增加图片启动刺激 + CSV自动保存
% 编码更新: 1=冒险(RG), 0=保守(ST), 2=未作答(Timeout)
% =========================================================================

prompt = {'请输入被试编号 (Subject ID):', '请输入被试姓名拼音 (Name Pinyin):'};
dlgtitle = '被试信息登记';
dims = [1 50];
definput = {'001', 'ZhangSan'};
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('主试取消了输入，程序终止。');
end
subID = answer{1};
subNamePinyin = answer{2};

try
    % 1. 初始设置与环境准备
    Screen('Preference', 'SkipSyncTests', 1); 
    PsychDefaultSetup(2);
    Screen('Preference', 'TextEncodingLocale', 'UTF-8'); 
    Screen('Preference', 'TextRenderer', 1);             
    rng('shuffle'); 
    
    KbName('UnifyKeyNames');
    keyLeft = KbName('LeftArrow');   
    keyRight = KbName('RightArrow'); 
    keyEscape = KbName('ESCAPE');    
    
    screens = Screen('Screens');
    screenNumber = max(screens);
    white = WhiteIndex(screenNumber);
    black = BlackIndex(screenNumber);
    red = [255 0 0]; 
    
    % 打开全屏窗口
    [window, windowRect] = PsychImaging('OpenWindow', screenNumber, black); 
    HideCursor();
    
    try
        Screen('TextFont', window, 'SimHei'); 
    catch
    end
    Screen('TextSize', window, 40);

    % =====================================================================
    % [新增]: 图片刺激准备
    % =====================================================================
    % 获取当前路径下的三个文件夹
    path_adv = fullfile(pwd, 'adventure');
    path_con = fullfile(pwd, 'conservative');
    path_neu = fullfile(pwd, 'neutral');
    
    % 扫描文件夹内的图片 (假设都是png，如果是jpg请修改后缀)
    files_adv = dir(fullfile(path_adv, 'a*.png'));
    files_con = dir(fullfile(path_con, 'c*.png'));
    files_neu = dir(fullfile(path_neu, 'n*.png'));
    
    % 检查图片数量是否足够
    if isempty(files_adv) || isempty(files_con) || isempty(files_neu)
        error('未找到图片文件！请检查adventure, conservative, neutral文件夹及图片命名是否为 .png 结尾。');
    end
    
    % 将各组图片顺序打乱
    files_adv = files_adv(randperm(length(files_adv)));
    files_con = files_con(randperm(length(files_con)));
    files_neu = files_neu(randperm(length(files_neu)));
    
    % 2. 实验参数与自适应变量初始化
    probabilities = [0.51, 0.63, 0.75, 0.83, 0.91];
    numProbs = length(probabilities);
    trialsPerProb = 8; 
    totalTrials = numProbs * trialsPerProb; % 共 40 试次
    
    % =====================================================================
    % [新增]: 试次启动条件分配 (1=Adventure, 2=Conservative, 3=Neutral)
    % =====================================================================
    % 40个试次大致平分为3类：14个冒险，13个保守，13个中立
    num_adv = ceil(totalTrials / 3); 
    num_con = round(totalTrials / 3);
    num_neu = totalTrials - num_adv - num_con;
    
    % 生成条件数组并打乱
    primeConditions = [ones(1, num_adv), 2*ones(1, num_con), 3*ones(1, num_neu)];
    primeConditions = primeConditions(randperm(totalTrials));
    
    % 计数器：记录各组图片目前用到了第几张
    img_counters = [1, 1, 1]; 
    
    isValidSeq = false;
    while ~isValidSeq
        trialList = repmat(1:numProbs, 1, trialsPerProb);
        trialList = trialList(randperm(totalTrials)); 
        
        isValidSeq = true;
        for i = 1:(totalTrials - 2)
            if trialList(i) == trialList(i+1) && trialList(i+1) == trialList(i+2)
                isValidSeq = false; 
                break;
            end
        end
    end
    
    % --- 记录初始 Alpha ---
    initial_alpha_est = 0.6 + 0.2 * rand(1, numProbs); 
    alpha_est = initial_alpha_est; 
    
    step_ladder = [0.1, 0.05, 0.02, 0.005]; 
    reversal_count = zeros(1, numProbs); 
    prev_choice = zeros(1, numProbs) - 1; 
    
    % 数据矩阵扩展到 11 列 (增加了 current_prime)
    dataMatrix = zeros(totalTrials, 11);
    record_imgNames = cell(totalTrials, 1); % 用 cell 记录每次呈现的图片名字文本
    
    % 3. 实验主循环
    welcome_text = sprintf('欢迎被试: %s (编号: %s)\n\n按任意键开始实验...', subNamePinyin, subID);
    DrawFormattedText(window, double(welcome_text), 'center', 'center', white);
    Screen('Flip', window);
    KbStrokeWait;
    
    for t = 1:totalTrials
        
        p_idx = trialList(t);
        p_val = probabilities(p_idx);
        current_alpha = alpha_est(p_idx);
        
        % =================================================================
        % [新增]: 在决策前呈现图片刺激
        % =================================================================
        current_prime = primeConditions(t); % 1=adv, 2=con, 3=neu
        
        if current_prime == 1
            % mod 防止图片用完报错，按顺序循环使用
            idx = mod(img_counters(1)-1, length(files_adv)) + 1; 
            img_name = files_adv(idx).name;
            img_path = fullfile(path_adv, img_name);
            img_counters(1) = img_counters(1) + 1;
        elseif current_prime == 2
            idx = mod(img_counters(2)-1, length(files_con)) + 1;
            img_name = files_con(idx).name;
            img_path = fullfile(path_con, img_name);
            img_counters(2) = img_counters(2) + 1;
        else
            idx = mod(img_counters(3)-1, length(files_neu)) + 1;
            img_name = files_neu(idx).name;
            img_path = fullfile(path_neu, img_name);
            img_counters(3) = img_counters(3) + 1;
        end
        
        % 记录当前图片名字到 cell 数组中
        record_imgNames{t} = img_name;
        
        % 读取图片并在屏幕中央生成纹理
        img_data = imread(img_path);
        img_tex = Screen('MakeTexture', window, img_data);
        
        % 画出图片并翻转屏幕
        Screen('DrawTexture', window, img_tex);
        Screen('Flip', window);
        
        % 图片呈现时间：当前设置为 2.0 秒
        WaitSecs(2.0); 
        
        % 释放图片内存，防止因加载过多图片导致内存泄露或闪退
        Screen('Close', img_tex); 
        
        % 呈现注视点作为缓冲 (ISI: 0.5 秒)
        DrawFormattedText(window, '+', 'center', 'center', white);
        Screen('Flip', window);
        WaitSecs(0.5);

        % =================================================================
        % 原有的风险决策计算与呈现
        % =================================================================
        ST_amount = randi([10, 20]); 
        RG_amount = ST_amount * (1/p_val)^(1/current_alpha);
        
        if RG_amount <= ST_amount + 0.1
            RG_amount = ST_amount + 0.1;
        elseif RG_amount > 100
            RG_amount = 100;
        end
        RG_amount = round(RG_amount); 
        
        st_side = randi(2);
        
        str_ST = sprintf('100%% 获得\n%d 元', ST_amount);
        str_RG = sprintf('%d%% 获得\n%d 元', p_val*100, RG_amount);
        
        if st_side == 1
            str_Left = str_ST;
            str_Right = str_RG;
        else
            str_Left = str_RG;
            str_Right = str_ST;
        end
        
        left_rect = [0, 0, windowRect(3) * 0.70, windowRect(4)];
        right_rect = [windowRect(3) * 0.30, 0, windowRect(3), windowRect(4)];

        DrawFormattedText(window, double(str_Left), 'center', 'center', white, [], [], [], 1.5, [], left_rect);
        DrawFormattedText(window, double(str_Right), 'center', 'center', white, [], [], [], 1.5, [], right_rect);
        DrawFormattedText(window, '+', 'center', 'center', white);

        vbl = Screen('Flip', window);
        
        respToBeMade = true;
        choice = 2; % 默认 2 (Timeout)
        rt = 0;
        reward = 0; 
        is_reversal = 0;
        
        while respToBeMade
            [keyIsDown, secs, keyCode] = KbCheck;
            
            if keyIsDown
                if keyCode(keyLeft)
                    rt = secs - vbl;
                    if st_side == 1
                        choice = 0; 
                    else
                        choice = 1; 
                    end
                    respToBeMade = false;
                elseif keyCode(keyRight)
                    rt = secs - vbl;
                    if st_side == 2
                        choice = 0; 
                    else
                        choice = 1; 
                    end
                    respToBeMade = false;
                elseif keyCode(keyEscape)
                    %ShowCursor(); 
                    sca;
                    error('实验被主试中止。');
                end
            end
            
            if (secs - vbl) >= 5.0
                respToBeMade = false;
                choice = 2;   
                rt = 5.0;     
            end
        end
        
        if choice == 2 
            warning_text = '作答超时！\n\n请集中注意力，在 5 秒内做出选择。';
            DrawFormattedText(window, double(warning_text), 'center', 'center', red);
            Screen('Flip', window);
            WaitSecs(2.0); 
            
        else 
            if choice == 0 
                reward = ST_amount;
            elseif choice == 1 
                if rand() <= p_val
                    reward = RG_amount; 
                else
                    reward = 0;         
                end
            end
            
            feedback_str = sprintf('获得 %d 元', reward);
            DrawFormattedText(window, double(feedback_str), 'center', 'center', white);
            Screen('Flip', window);
            WaitSecs(1.0); 
            
            if prev_choice(p_idx) ~= -1 && prev_choice(p_idx) ~= choice
                is_reversal = 1;
                reversal_count(p_idx) = reversal_count(p_idx) + 1;
            end
            
            step_idx = min(reversal_count(p_idx) + 1, length(step_ladder));
            current_step = step_ladder(step_idx);
            
            if choice == 0 
                alpha_est(p_idx) = alpha_est(p_idx) - current_step;
            elseif choice == 1 
                alpha_est(p_idx) = alpha_est(p_idx) + current_step;
            end
            
            if alpha_est(p_idx) < 0.2
                alpha_est(p_idx) = 0.2;
            elseif alpha_est(p_idx) > 2.0
                alpha_est(p_idx) = 2.0;
            end
            
            prev_choice(p_idx) = choice;
        end
        
        % 记录数据：将 current_prime (刺激条件) 作为第 11 列记录
        dataMatrix(t,:) = [t, p_idx, p_val, ST_amount, RG_amount, current_alpha, choice, rt, is_reversal, reward, current_prime];
        
        Screen('Flip', window);
        WaitSecs(0.5);
        
    end
    
    DrawFormattedText(window, double('实验结束，感谢您的参与！\n\n数据正在保存，请按任意键退出...'), 'center', 'center', white);
    Screen('Flip', window);
    KbStrokeWait;
    
    %ShowCursor(); 
    sca;
    
    % =====================================================================
    % 数据处理与 CSV 文件保存
    % =====================================================================
    
    % 转换按键标签
    choice_labels = cell(totalTrials, 1);
    for i = 1:totalTrials
        if dataMatrix(i, 7) == 0
            choice_labels{i} = 'ST';
        elseif dataMatrix(i, 7) == 1
            choice_labels{i} = 'RG';
        elseif dataMatrix(i, 7) == 2
            choice_labels{i} = 'Timeout';
        end
    end
    
    % [新增]: 转换图片刺激条件的文本标签
    prime_labels = cell(totalTrials, 1);
    for i = 1:totalTrials
        if dataMatrix(i, 11) == 1
            prime_labels{i} = 'Adventure';
        elseif dataMatrix(i, 11) == 2
            prime_labels{i} = 'Conservative';
        else
            prime_labels{i} = 'Neutral';
        end
    end
    
    subID_col = repmat({subID}, totalTrials, 1);
    
    % 合并主数据表: 增加了 Prime_Condition 和 Image_Name 两列
    dataTable = table(subID_col, dataMatrix(:,1), prime_labels, record_imgNames, ...
                      dataMatrix(:,3), dataMatrix(:,6), ...
                      dataMatrix(:,4), dataMatrix(:,5), dataMatrix(:,7), ...
                      choice_labels, dataMatrix(:,8), dataMatrix(:,9), dataMatrix(:,10), ...
                      'VariableNames', {'SubID', 'Trial', 'Prime_Condition', 'Image_Name', ...
                                        'Probability', 'Alpha_Est', ...
                                        'ST_Amount', 'RG_Amount', 'Choice_Num', ...
                                        'Choice_Label', 'RT_sec', 'Is_Reversal', 'Reward'});
                                        
    % 保存主数据表
    mainFileName = sprintf('RiskDM_Data_%s_%s.csv', subID, subNamePinyin);
    writetable(dataTable, mainFileName);
    
    % 单独保存 Alpha 数据表
    alphaTable = table(probabilities', initial_alpha_est', alpha_est', ...
                       'VariableNames', {'Probability', 'Initial_Alpha', 'Final_Alpha'});
    alphaFileName = sprintf('RiskDM_Alpha_%s_%s.csv', subID, subNamePinyin);
    writetable(alphaTable, alphaFileName);
    
    % --- 终端打印提示 ---
    disp(' ');
    fprintf('=== 被试: %s (编号: %s) 数据已成功保存 ===\n', subNamePinyin, subID);
    fprintf('1. 试次行为数据: %s\n', mainFileName);
    fprintf('2. Alpha结果数据: %s\n', alphaFileName);
    disp('====================================================================');
    
catch
    %ShowCursor(); 
    sca;
    psychrethrow(psychlasterror);
end