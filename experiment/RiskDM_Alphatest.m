% =========================================================================
% 风险决策自适应任务 (Gain Framework) - 白底黑字版
% 编码更新: 1=冒险(RG), 0=保守(ST), 2=未作答(Timeout)
% =========================================================================
prompt = {'请输入被试编号 (Subject ID):', '请输入被试姓名拼音 (Name Pinyin):', '请输入年龄 (Age):', '请输入性别 (Gender, 例如 M/F):'};
dlgtitle = '被试信息登记';
dims = [1 50];
definput = {'', '', '', ''}; 
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('主试取消了输入，程序终止。');
end
subID = answer{1};
subNamePinyin = answer{2};
subAge = answer{3};    
subGender = answer{4}; 

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
    
    % --- 颜色定义修改 ---
    white = WhiteIndex(screenNumber);
    black = BlackIndex(screenNumber);
    bgColor = white;    % 背景色为白色
    textColor = black;  % 文字色为黑色
    red = [255 0 0];    % 警告色保持红色
    
    % 打开窗口，背景设为 bgColor (白色)
    % [window, windowRect] = PsychImaging('OpenWindow', screenNumber, bgColor); 
    [window, windowRect] = PsychImaging('OpenWindow', screenNumber, bgColor, [0, 0, 1024, 768]);
    HideCursor();
    
    try
        Screen('TextFont', window, 'SimHei'); 
    catch
    end
    Screen('TextSize', window, 40);
    
    % ==========================================================
    % 2. 实验参数与序列初始化
    % ==========================================================
    numBlocks = 5; 
    trialsPerBlock = 32; 
    totalTrials = numBlocks * trialsPerBlock; 
    
    probabilities = [0.18, 0.27, 0.36 , 0.45, 0.54, 0.63, 0.72, 0.81];
    numProbs = length(probabilities);
    trialsPerProbBlock = trialsPerBlock / numProbs; 
    
    trialList = zeros(1, totalTrials);
    st_sides_list = zeros(1, totalTrials);
    
    for b = 1:numBlocks
        startIndex = (b - 1) * trialsPerBlock + 1;
        endIndex = b * trialsPerBlock;
        
        blockProbs = repmat(1:numProbs, 1, trialsPerProbBlock);
        blockProbs = blockProbs(randperm(trialsPerBlock)); 
        for scan = 1:5
            for i = 3:trialsPerBlock
                if blockProbs(i) == blockProbs(i-1) && blockProbs(i-1) == blockProbs(i-2)
                    for j = i+1:trialsPerBlock
                        if blockProbs(j) ~= blockProbs(i)
                            temp = blockProbs(i); blockProbs(i) = blockProbs(j); blockProbs(j) = temp;
                            break;
                        end
                    end
                end
            end
        end
        trialList(startIndex:endIndex) = blockProbs;
        
        blockSides = [ones(1, trialsPerBlock/2), 2 * ones(1, trialsPerBlock/2)]; 
        blockSides = blockSides(randperm(trialsPerBlock)); 
        for scan = 1:5 
            for i = 3:trialsPerBlock
                if blockSides(i) == blockSides(i-1) && blockSides(i-1) == blockSides(i-2)
                    for j = i+1:trialsPerBlock
                        if blockSides(j) ~= blockSides(i)
                            temp = blockSides(i); blockSides(i) = blockSides(j); blockSides(j) = temp;
                            break;
                        end
                    end
                end
            end
        end
        st_sides_list(startIndex:endIndex) = blockSides;
    end
    
    step_ladder = [0.1, 0.05, 0.02, 0.01, 0.005]; 
    alpha_est = 0.6 + 0.2 * rand(); 
    dataMatrix = zeros(totalTrials, 11);
    block_initial_alphas = zeros(1, numBlocks);
    block_final_alphas = zeros(1, numBlocks);
    
    % 3. 实验主循环
    welcome_text = sprintf('欢迎被试: %s (编号: %s)\n\n选左边选项请按左键，选右边选项请按右键\n\n按任意键开始实验...', subNamePinyin, subID);
    DrawFormattedText(window, double(welcome_text), 'center', 'center', textColor); % 文字为黑色
    Screen('Flip', window);
    KbStrokeWait;
    
    for t = 1:totalTrials
        current_block = ceil(t / trialsPerBlock);
        if mod(t - 1, trialsPerBlock) == 0
            reversal_count = 0;             
            prev_choice = -1;               
            block_initial_alphas(current_block) = alpha_est; 
        end
        
        p_idx = trialList(t);
        p_val = probabilities(p_idx);
        current_alpha = alpha_est; 
        
        ST_amount = randi([11, 24]); 
        RG_amount = ST_amount * (1/p_val)^(1/current_alpha);
        
        if RG_amount <= ST_amount + 0.1; RG_amount = ST_amount + 0.1;
        elseif RG_amount > 100; RG_amount = 100; end
        RG_amount = round(RG_amount); 
        
        st_side = st_sides_list(t);
        str_ST = sprintf('100%% 获得\n%d 元', ST_amount);
        str_RG = sprintf('%.0f%% 获得\n%d 元', p_val*100, RG_amount);
        
        if st_side == 1; str_Left = str_ST; str_Right = str_RG;
        else; str_Left = str_RG; str_Right = str_ST; end
        
        left_rect = [0, 0, windowRect(3) * 0.70, windowRect(4)];
        right_rect = [windowRect(3) * 0.30, 0, windowRect(3), windowRect(4)];
        
        % 刺激呈现 (黑字)
        DrawFormattedText(window, double(str_Left), 'center', 'center', textColor, [], [], [], 1.5, [], left_rect);
        DrawFormattedText(window, double(str_Right), 'center', 'center', textColor, [], [], [], 1.5, [], right_rect);
        DrawFormattedText(window, '+', 'center', 'center', textColor);
        
        vbl = Screen('Flip', window);
        [~, ~, prevKeyCode] = KbCheck; 
        respToBeMade = true;
        choice = 2; rt = 0; reward = 0; is_reversal = 0;
        
        while respToBeMade
            [keyIsDown, secs, currKeyCode] = KbCheck;
            newKeys = currKeyCode & ~prevKeyCode; 
            if any(newKeys)
                if newKeys(keyLeft)
                    rt = secs - vbl;
                    if st_side == 1; choice = 0; else; choice = 1; end
                    respToBeMade = false;
                elseif newKeys(keyRight)
                    rt = secs - vbl;
                    if st_side == 2; choice = 0; else; choice = 1; end
                    respToBeMade = false;
                elseif newKeys(keyEscape)
                    ShowCursor(); sca; error('实验被主试中止。');
                end
            end
            prevKeyCode = currKeyCode;
            if (secs - vbl) >= 5.0
                respToBeMade = false; choice = 2; rt = 5.0;     
            end
        end
        
        if choice == 2 
            warning_text = '作答超时！\n\n请集中注意力，在 5 秒内做出选择。';
            DrawFormattedText(window, double(warning_text), 'center', 'center', red); % 保持红色
            Screen('Flip', window);
            WaitSecs(2.0); 
        else 
            if choice == 0; reward = ST_amount;
            elseif choice == 1; if rand() <= p_val; reward = RG_amount; else; reward = 0; end
            end
            
            feedback_str = sprintf('获得 %d 元', reward);
            DrawFormattedText(window, double(feedback_str), 'center', 'center', textColor); % 反馈黑字
            Screen('Flip', window);
            WaitSecs(1.0); 
            
            if prev_choice ~= -1 && prev_choice ~= choice
                is_reversal = 1;
                reversal_count = reversal_count + 1;
            end
            step_idx = min(reversal_count + 1, length(step_ladder));
            current_step = step_ladder(step_idx);
            
            if choice == 0; alpha_est = alpha_est - current_step;
            elseif choice == 1; alpha_est = alpha_est + current_step; end
            
            if alpha_est < 0.2; alpha_est = 0.2;
            elseif alpha_est > 2.0; alpha_est = 2.0; end
            prev_choice = choice;
        end
        
        dataMatrix(t,:) = [current_block, t, p_idx, p_val, ST_amount, RG_amount, current_alpha, choice, rt, is_reversal, reward];
        
        Screen('Flip', window);
        WaitSecs(0.5);
        
        if mod(t, trialsPerBlock) == 0 
            block_final_alphas(current_block) = alpha_est; 
            if t < totalTrials 
                rest_text = sprintf('第 %d / %d 组完成！\n\n您可以稍作休息放松眼睛。\n\n准备好后，请按任意键继续实验...', current_block, numBlocks);
                DrawFormattedText(window, double(rest_text), 'center', 'center', textColor); % 休息界面黑字
                Screen('Flip', window);
                WaitSecs(0.5);   
                KbReleaseWait;   
                KbWait;          
            end
        end
    end
    
    DrawFormattedText(window, double('实验结束，感谢您的参与！\n\n数据正在保存，请按任意键退出...'), 'center', 'center', textColor);
    Screen('Flip', window);
    KbReleaseWait; KbWait;
    
    ShowCursor(); sca;
    
    % 数据处理与保存
    choice_labels = cell(totalTrials, 1);
    for i = 1:totalTrials
        if dataMatrix(i, 8) == 0; choice_labels{i} = 'ST';
        elseif dataMatrix(i, 8) == 1; choice_labels{i} = 'RG';
        elseif dataMatrix(i, 8) == 2; choice_labels{i} = 'Timeout'; end
    end
    
    subID_col = repmat({subID}, totalTrials, 1);
    subAge_col = repmat({subAge}, totalTrials, 1);
    subGender_col = repmat({subGender}, totalTrials, 1);
    
    dataTable = table(subID_col, subAge_col, subGender_col, ...
                      dataMatrix(:,1), dataMatrix(:,2), dataMatrix(:,4), dataMatrix(:,7), ...
                      dataMatrix(:,5), dataMatrix(:,6), dataMatrix(:,8), ...
                      choice_labels, dataMatrix(:,9), dataMatrix(:,10), dataMatrix(:,11), ...
                      'VariableNames', {'SubID', 'Age', 'Gender', 'Block', 'Trial', ...
                                        'Probability', 'Alpha_Est', 'ST_Amount', 'RG_Amount', ...
                                        'Choice_Num', 'Choice_Label', 'RT_sec', 'Is_Reversal', 'Reward'});
                                        
    mainFileName = sprintf('RiskDM_Data_%s_%s.csv', subID, subNamePinyin);
    writetable(dataTable, mainFileName);
    
    block_col = (1:numBlocks)';
    alphaTable = table(block_col, block_initial_alphas', block_final_alphas', ...
                       'VariableNames', {'Block_Num', 'Initial_Alpha', 'Final_Alpha'});
    alphaFileName = sprintf('RiskDM_Alpha_%s_%s.csv', subID, subNamePinyin);
    writetable(alphaTable, alphaFileName);
    
    sorted_alphas = sort(block_final_alphas); 
    trimmed_alphas = sorted_alphas(2:4);      
    final_mean_alpha = mean(trimmed_alphas);  
    
    disp(' ');
    fprintf('=== 被试: %s (编号: %s) 数据已成功保存 ===\n', subNamePinyin, subID);
    fprintf('1. 试次行为数据: %s\n', mainFileName);
    fprintf('2. 分块Alpha结果: %s\n', alphaFileName);
    fprintf('--------------------------------------------------------------------\n');
    fprintf('【核心指标】切尾平均 Alpha (去极值后) = %.4f\n', final_mean_alpha);
    disp('====================================================================');
    
catch
    ShowCursor(); sca;
    psychrethrow(psychlasterror);
end
random_number = randi([1, 160]);
disp(random_number);