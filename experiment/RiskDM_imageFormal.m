% =========================================================================
% 风险决策正式实验 (Gain Framework) - 最终安全版 v5 (增加试次临界Alpha记录)
% 更新: 增加 Trial_Indif_Alpha 列用于记录每次刺激实际对应的等价 Alpha
% 特性: 固定 Alpha, 1/3图片尺寸(2s), 拉丁方, Jitter注视点, 实时保存, xlsx防乱码
% =========================================================================

% 清理工作区和屏幕
sca;
close all;
clear;

% --- 1. 信息登记与参数输入 ---
prompt = {'请输入被试编号 (Subject ID, 纯数字):', '请输入被试姓名拼音:', '请输入年龄:', '请输入性别 (M/F):', '请输入基线 Alpha 值 (前测结果):'};
dlgtitle = '正式实验信息登记';
dims = [1 50];
definput = {'', '', '', '', ''}; 
answer = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(answer)
    error('主试取消了输入，程序终止。');
end

subID = answer{1};
subNamePinyin = answer{2};
subAge = answer{3};    
subGender = answer{4}; 
baseline_alpha = str2double(answer{5}); 

if isnan(baseline_alpha) || baseline_alpha <= 0
    error('Alpha 值输入有误，必须为大于0的数字。');
end

% 定义主数据文件名
mainFileName = sprintf('RiskDM_FormalData_%s_%s.xlsx', subID, subNamePinyin);
% 定义实时保存的 TXT 文件名
rawTxtName = sprintf('Backup_RiskDM_%s_%s.txt', subID, subNamePinyin);

% 初始化已完成试次计数器
t_completed = 0; 
fid = -1; 

try
    % 打开 TXT 文件，强制使用 UTF-8 编码写入
    fid = fopen(rawTxtName, 'a', 'n', 'UTF-8');
    if fid == -1
        error('无法创建备份文件，请检查当前文件夹的写入权限。');
    end
    % 写入 TXT 表头 (新增 Trial_Indif_Alpha)
    fprintf(fid, 'SubID,Age,Gender,Baseline_Alpha,Block,Trial,Condition,Image_Name,Probability,ST_Amount,RG_Amount,Choice_Num,Choice_Label,RT_sec,Reward,Trial_Indif_Alpha\n');

    % --- 2. PTB 初始化与屏幕设置 ---
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
    bgColor = white;     
    textColor = black;   
    red = [255 0 0];     
    
    % [window, windowRect] = PsychImaging('OpenWindow', screenNumber, bgColor); 
    [window, windowRect] = PsychImaging('OpenWindow', screenNumber, bgColor, [0, 0, 1024, 768]);
    HideCursor();
    
    try Screen('TextFont', window, 'SimHei'); catch; end
    Screen('TextSize', window, 40);
    
    % --- 3. 读取图片文件信息 ---
    base_img_path = 'F:\Desktop\risk\';
    cond_folders = {'neutral', 'adventure', 'conservative'}; 
    img_files_list = cell(1, 3);
    
    for c = 1:3
        folder_path = fullfile(base_img_path, cond_folders{c});
        files = [dir(fullfile(folder_path, '*.jpg')); dir(fullfile(folder_path, '*.png')); dir(fullfile(folder_path, '*.bmp')); dir(fullfile(folder_path, '*.jpeg'))];
        if isempty(files)
            sca; error('在路径 %s 中没有找到图片文件！', folder_path);
        end
        img_files_list{c} = {files.name}; 
    end
    
    % --- 4. 拉丁方条件平衡与序列生成 ---
    numBlocks = 9; 
    trialsPerBlock = 24; 
    totalTrials = numBlocks * trialsPerBlock; 
    
    sub_num = str2double(subID);
    if isnan(sub_num); sub_num = randi(100); end 
    
    rem_val = mod(sub_num, 3);
    if rem_val == 1; designated_first = 1;     
    elseif rem_val == 2; designated_first = 2; 
    else; designated_first = 3; end            
    
    conditions = [1, 2, 3]; 
    blockConditionList = zeros(1, numBlocks);
    
    rem_conds = setdiff(conditions, designated_first);
    rem_conds = rem_conds(randperm(2));
    blockConditionList(1:3) = [designated_first, rem_conds];
    
    for cycle = 2:3
        current_perm = conditions(randperm(3));
        while current_perm(1) == blockConditionList((cycle-1)*3)
            current_perm = conditions(randperm(3)); 
        end
        blockConditionList((cycle-1)*3+1 : cycle*3) = current_perm;
    end
    
    % --- 5. 试次参数初始化 ---
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
    
    % 数据记录矩阵扩大为 10 列 (新增第10列 Trial_Indif_Alpha)
    dataMatrix = zeros(totalTrials, 10); 
    record_conds = cell(totalTrials, 1);
    record_images = cell(totalTrials, 1);
    
    % --- 6. 实验主循环 ---
    welcome_text = sprintf('欢迎被试: %s (编号: %s)\n\n这部分是正式实验。\n\n选左边选项请按左键，选右边选项请按右键\n\n按任意键开始实验...', subNamePinyin, subID);
    DrawFormattedText(window, double(welcome_text), 'center', 'center', textColor); 
    Screen('Flip', window);
    KbStrokeWait;
    
    for t = 1:totalTrials
        
        current_block = ceil(t / trialsPerBlock);
        current_cond = blockConditionList(current_block);
        cond_name = cond_folders{current_cond};
        current_img_list = img_files_list{current_cond};
        
        if mod(t - 1, trialsPerBlock) == 0
            shuffled_img_indices = randperm(length(current_img_list));
        end
        
        p_idx = trialList(t);
        p_val = probabilities(p_idx);
        
        % 计算金额并取整
        ST_amount = randi([11, 24]); 
        RG_amount = ST_amount * (1/p_val)^(1/baseline_alpha);
        if RG_amount <= ST_amount + 0.1; RG_amount = ST_amount + 0.1;
        elseif RG_amount > 100; RG_amount = 100; end
        RG_amount = round(RG_amount); 
        
        % --- 新增逻辑：计算试次实际呈现的临界 Alpha ---
        % 公式: Alpha = ln(1/p) / ln(RG/ST)
        if RG_amount > ST_amount
            trial_indif_alpha = log(1/p_val) / log(RG_amount / ST_amount);
        else
            trial_indif_alpha = NaN; % 极端防错，正常情况下RG总是大于ST
        end
        % ------------------------------------------------
        
        img_id = shuffled_img_indices(mod(t-1, trialsPerBlock) + 1); 
        if img_id > length(current_img_list); img_id = mod(img_id, length(current_img_list)) + 1; end 
        img_filename = current_img_list{img_id};
        img_full_path = fullfile(base_img_path, cond_name, img_filename);
        
        record_conds{t} = cond_name;
        record_images{t} = img_filename;
        
        % 1. 呈现图片 (2s, 1/3尺寸)
        img_data = imread(img_full_path);
        [img_h, img_w, ~] = size(img_data); 
        dstRect = CenterRect([0, 0, img_w/3, img_h/3], windowRect); 
        img_tex = Screen('MakeTexture', window, img_data);
        Screen('DrawTexture', window, img_tex, [], dstRect); 
        Screen('Flip', window);
        WaitSecs(2.0); 
        Screen('Close', img_tex); 
        
        % 2. 呈现注视点
        DrawFormattedText(window, '+', 'center', 'center', textColor);
        Screen('Flip', window);
        WaitSecs(0.8 + 0.4 * rand());
        
        % 3. 决策界面呈现
        st_side = st_sides_list(t);
        str_ST = sprintf('100%% 获得\n%d 元', ST_amount);
        str_RG = sprintf('%.0f%% 获得\n%d 元', p_val*100, RG_amount);
        if st_side == 1; str_Left = str_ST; str_Right = str_RG;
        else; str_Left = str_RG; str_Right = str_ST; end
        
        left_rect = [0, 0, windowRect(3) * 0.70, windowRect(4)];
        right_rect = [windowRect(3) * 0.30, 0, windowRect(3), windowRect(4)];
        DrawFormattedText(window, double(str_Left), 'center', 'center', textColor, [], [], [], 1.5, [], left_rect);
        DrawFormattedText(window, double(str_Right), 'center', 'center', textColor, [], [], [], 1.5, [], right_rect);
        DrawFormattedText(window, '+', 'center', 'center', textColor);
        
        vbl = Screen('Flip', window);
        [~, ~, prevKeyCode] = KbCheck; 
        respToBeMade = true;
        choice = 2; rt = 0; reward = 0; 
        
        % 等待按键
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
                    error('主试按下了 ESC 键，实验被强行中止。');
                end
            end
            prevKeyCode = currKeyCode;
            if (secs - vbl) >= 5.0
                respToBeMade = false; choice = 2; rt = 5.0;     
            end
        end
        
        % 4. 结果反馈
        if choice == 2 
            DrawFormattedText(window, double('作答超时！\n\n请在 5 秒内做出选择。'), 'center', 'center', red);
            Screen('Flip', window);
            WaitSecs(2.0); 
            choice_lbl_txt = 'Timeout';
        else 
            if choice == 0; reward = ST_amount; choice_lbl_txt = 'ST';
            elseif choice == 1
                if rand() <= p_val; reward = RG_amount; else; reward = 0; end
                choice_lbl_txt = 'RG';
            end
            DrawFormattedText(window, double(sprintf('获得 %d 元', reward)), 'center', 'center', textColor); 
            Screen('Flip', window);
            WaitSecs(1.0); 
        end
        
        % 5. 反馈后注视点
        DrawFormattedText(window, '+', 'center', 'center', textColor);
        Screen('Flip', window);
        WaitSecs(0.8 + 0.4 * rand());
        
        % --- 数据记录与实时写入 ---
        current_trial_in_block = mod(t-1, trialsPerBlock)+1;
        % 将 Trial_Indif_Alpha 存入第10列
        dataMatrix(t,:) = [current_block, current_trial_in_block, p_idx, p_val, ST_amount, RG_amount, choice, rt, reward, trial_indif_alpha];
        
        % 实时写入 TXT 文件 (新增 %4.f 记录 trial_indif_alpha)
        fprintf(fid, '%s,%s,%s,%.4f,%d,%d,%s,%s,%.2f,%d,%d,%d,%s,%.4f,%d,%.4f\n', ...
            subID, subAge, subGender, baseline_alpha, current_block, current_trial_in_block, ...
            cond_name, img_filename, p_val, ST_amount, RG_amount, choice, choice_lbl_txt, rt, reward, trial_indif_alpha);
            
        t_completed = t; 
        
        % 7. Block 间强制休息
        if mod(t, trialsPerBlock) == 0 && current_block < numBlocks
            start_rest_time = GetSecs;
            while (GetSecs - start_rest_time) < 30 
                remain_time = ceil(30 - (GetSecs - start_rest_time));
                rest_text = sprintf('第 %d / %d 组完成！\n\n请务必休息放松眼睛。\n\n强制休息倒计时: %d 秒', current_block, numBlocks, remain_time);
                DrawFormattedText(window, double(rest_text), 'center', 'center', textColor);
                Screen('Flip', window);
                WaitSecs(0.1); 
            end
            DrawFormattedText(window, double('休息结束！\n\n准备好后，请按任意键继续下一组...'), 'center', 'center', textColor); 
            Screen('Flip', window);
            WaitSecs(0.5); KbReleaseWait; KbWait;          
        end
    end
    
    % --- 8. 实验正常结束 ---
    DrawFormattedText(window, double('正式实验结束，感谢您的参与！\n\n数据正在保存...'), 'center', 'center', textColor); 
    Screen('Flip', window);
    WaitSecs(2); 
    
    if fid ~= -1; fclose(fid); end 
    ShowCursor(); sca;
    
    % 正常生成完整 xlsx
    save_final_excel(subID, subNamePinyin, subAge, subGender, baseline_alpha, t_completed, dataMatrix, record_conds, record_images, mainFileName);
    disp('====================================================================');
    disp('实验正常结束。完整数据已保存为 Excel 文件！');
    disp(['完整数据路径: ', fullfile(pwd, mainFileName)]);
    
catch ME
    if fid ~= -1; fclose(fid); end 
    ShowCursor(); 
    sca;
    
    disp('======================== 警告 ========================');
    disp('实验异常终止（可能是按下了 ESC 或程序报错）！');
    disp(['错误信息: ', ME.message]);
    
    if t_completed > 0
        % 生成中断前的数据 (保存为 xlsx)
        crashFileName = sprintf('CrashSaved_RiskDM_%s_%s_Trials%d.xlsx', subID, subNamePinyin, t_completed);
        save_final_excel(subID, subNamePinyin, subAge, subGender, baseline_alpha, t_completed, dataMatrix, record_conds, record_images, crashFileName);
        disp('【成功抢救数据】中断前的部分数据已保存为 Excel 和 TXT 备份！');
        disp(['抢救生成的文件: ', fullfile(pwd, crashFileName)]);
    else
        disp('实验在第一个 Trial 完成前中断，未保存有效试次数据。');
    end
    disp('======================================================');
end

% =========================================================================
% 辅助函数：生成并保存为 xlsx 文件 (增加 Trial_Indif_Alpha 列)
% =========================================================================
function save_final_excel(subID, subNamePinyin, subAge, subGender, alpha, num_trials, dataMatrix, record_conds, record_images, fileName)
    
    dat = dataMatrix(1:num_trials, :);
    conds = record_conds(1:num_trials);
    imgs = record_images(1:num_trials);
    
    choice_labels = cell(num_trials, 1);
    for i = 1:num_trials
        if dat(i, 7) == 0; choice_labels{i} = 'ST';
        elseif dat(i, 7) == 1; choice_labels{i} = 'RG';
        elseif dat(i, 7) == 2; choice_labels{i} = 'Timeout'; end
    end
    
    subID_col = repmat({subID}, num_trials, 1);
    subAge_col = repmat({subAge}, num_trials, 1);
    subGender_col = repmat({subGender}, num_trials, 1);
    alpha_col = repmat(alpha, num_trials, 1);
    
    % 添加 dat(:,10) 并在 VariableNames 结尾加上 Trial_Indif_Alpha
    dataTable = table(subID_col, subAge_col, subGender_col, alpha_col, ...
                      dat(:,1), dat(:,2), conds, imgs, ...
                      dat(:,4), dat(:,5), dat(:,6), ...
                      dat(:,7), choice_labels, dat(:,8), dat(:,9), dat(:,10), ...
                      'VariableNames', {'SubID', 'Age', 'Gender', 'Baseline_Alpha', 'Block', 'Trial', ...
                                        'Condition', 'Image_Name', 'Probability', 'ST_Amount', 'RG_Amount', ...
                                        'Choice_Num', 'Choice_Label', 'RT_sec', 'Reward', 'Trial_Indif_Alpha'});
                                        
    writetable(dataTable, fileName);
end
random_number = randi([1, 216]);
disp(random_number);