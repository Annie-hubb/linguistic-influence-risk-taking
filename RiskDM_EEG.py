# -*- coding: utf-8 -*-
# =========================================================================
# 风险决策自适应任务 (Gain Framework) - EEG 版本
# 从 MATLAB (Psychtoolbox) RiskDM_withpicture.m 忠实迁移到 PsychoPy
#
# 编码: 1=冒险(RG), 0=保守(ST), 2=未作答(Timeout)
#
# EEG 修改 (仅此两处, 其余逻辑与 MATLAB 完全一致):
#   1. Prime 图片出现的那一帧: 图片 + 左下角 200x200 白色方块 同帧 Flip,
#      等待 50ms 后刷新屏幕只保留图片 (photodiode 视觉 trigger, 竖直线)
#   2. Feedback 出现的那一帧: Feedback 文字 + 左下角 200x200 白色方块 同帧 Flip,
#      等待 50ms 后刷新屏幕只保留 Feedback 文字
#   方块位置与实验室测试代码 test_trigger_tone.m 完全一致:
#      square = [0 0 200 200]; CenterRectOnPointd(square, 10, rect(4)-10)
#      即方块中心位于 (x=10, y=屏幕高度-10), 屏幕左下角
#   键盘 trigger 与声音 trigger 由实验室设备自动记录, 代码中不做任何硬件发送。
#
# 新增数据字段 (仅这四个):
#   Prime_Code:          11=Adventure, 12=Conservative, 13=Neutral
#   Feedback_Code:       21=ST feedback, 22=RG win, 23=RG loss (Timeout 为空)
#   Prime_Onset_Time:    Prime trigger 帧 Flip 时刻 (实验时钟, 秒)
#   Feedback_Onset_Time: Feedback trigger 帧 Flip 时刻 (实验时钟, 秒; Timeout 为空)
#
# 输出 (保存在脚本所在目录):
#   RiskDM_Data_<subID>_<Name>.csv
#   RiskDM_Alpha_<subID>_<Name>.csv
# =========================================================================

import os
import csv
import glob
import math
import random
import traceback

from psychopy import visual, core, event, gui

# 以脚本所在目录为基准目录 (图片文件夹与数据输出都在这里,
# 与 MATLAB 在脚本目录下运行 pwd 的行为一致, 不受终端当前目录影响)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# -------------------------------------------------------------------------
# 常量: 与 MATLAB 保持一致的 timing
# -------------------------------------------------------------------------
PRIME_DUR    = 2.0     # 图片呈现总时长 (秒)
ISI_DUR      = 0.5     # 注视点缓冲 (秒)
DECISION_MAX = 5.0     # 决策最长时限 (秒)
JITTER_MIN   = 0.8     # Feedback 前 Jitter 下限 (秒)
JITTER_MAX   = 1.2     # Feedback 前 Jitter 上限 (秒)
FEEDBACK_DUR = 1.0     # Feedback 呈现总时长 (秒)
TIMEOUT_DUR  = 2.0     # 超时提示呈现时长 (秒)
ITI_DUR      = 0.5     # 试次间隔 (秒)
TRIGGER_DUR  = 0.05    # 视觉 trigger 方块持续时间 50ms (与实验室方案一致)


def matlab_round(x):
    """MATLAB 的 round(): 四舍五入, 0.5 远离零 (Python round 是银行家舍入)。"""
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


# =========================================================================
# 被试信息登记 (对应 MATLAB inputdlg)
# =========================================================================
dlg = gui.Dlg(title='被试信息登记')
dlg.addField('请输入被试编号 (Subject ID):', '001')
dlg.addField('请输入被试姓名拼音 (Name Pinyin):', 'ZhangSan')
dlg_data = dlg.show()
if not dlg.OK:
    raise SystemExit('主试取消了输入，程序终止。')
if isinstance(dlg_data, dict):
    dlg_values = list(dlg_data.values())
else:
    dlg_values = list(dlg_data)
subID = str(dlg_values[0]).strip()
subNamePinyin = str(dlg_values[1]).strip()

win = None
try:
    # =====================================================================
    # 1. 初始设置与环境准备
    # =====================================================================
    random.seed()  # 对应 rng('shuffle')

    win = visual.Window(
        fullscr=True,
        color=(-1, -1, -1),      # 黑色背景 (对应 BlackIndex)
        colorSpace='rgb',
        units='pix',
        allowGUI=False,
    )
    win.mouseVisible = False     # 对应 HideCursor

    win_w, win_h = win.size      # 对应 windowRect(3), windowRect(4)

    FONT_NAME = 'SimHei'
    TEXT_SIZE = 40

    WHITE = (1, 1, 1)
    RED = (1, -1, -1)            # 对应 [255 0 0]

    def make_text(text, pos=(0, 0), color=WHITE, height=TEXT_SIZE, wrap=None):
        return visual.TextStim(
            win, text=text, pos=pos, color=color, colorSpace='rgb',
            font=FONT_NAME, height=height, wrapWidth=wrap, units='pix',
        )

    # ---------------------------------------------------------------------
    # 视觉 Trigger 方块 (严格按照 test_trigger_tone.m)
    # square = [0 0 200 200]
    # squareCoords = CenterRectOnPointd(square, 10, rect(4)-10)
    # PTB 坐标 (左上原点) 中心点 (10, height-10)
    # 转换为 PsychoPy 中心原点坐标: (10 - W/2, -H/2 + 10)  -> 屏幕左下角
    # ---------------------------------------------------------------------
    trigger_square = visual.Rect(
        win, width=200, height=200, units='pix',
        pos=(10 - win_w / 2.0, 10 - win_h / 2.0),
        fillColor=(1, 1, 1), fillColorSpace='rgb', lineColor=None,
    )

    # 注视点
    fixation = make_text('+')

    # =====================================================================
    # [图片刺激准备] (与 MATLAB 一致)
    # =====================================================================
    path_adv = os.path.join(BASE_DIR, 'adventure')
    path_con = os.path.join(BASE_DIR, 'conservative')
    path_neu = os.path.join(BASE_DIR, 'neutral')

    files_adv = sorted(glob.glob(os.path.join(path_adv, 'a*.png')))
    files_con = sorted(glob.glob(os.path.join(path_con, 'c*.png')))
    files_neu = sorted(glob.glob(os.path.join(path_neu, 'n*.png')))

    if not files_adv or not files_con or not files_neu:
        raise RuntimeError('未找到图片文件！请检查 %s 下的 adventure, conservative, '
                           'neutral 文件夹及图片命名是否为 .png 结尾。' % BASE_DIR)

    # 将各组图片顺序打乱 (对应 randperm)
    random.shuffle(files_adv)
    random.shuffle(files_con)
    random.shuffle(files_neu)

    # =====================================================================
    # 2. 实验参数与自适应变量初始化 (与 MATLAB 完全一致)
    # =====================================================================
    probabilities = [0.51, 0.63, 0.75, 0.83, 0.91]
    numProbs = len(probabilities)
    trialsPerProb = 8
    totalTrials = numProbs * trialsPerProb   # 共 40 试次

    # ---------------------------------------------------------------------
    # 试次启动条件分配 (1=Adventure, 2=Conservative, 3=Neutral)
    # 40个试次大致平分为3类：14个冒险，13个保守，13个中立
    # ---------------------------------------------------------------------
    num_adv = math.ceil(totalTrials / 3)                 # ceil(40/3) = 14
    num_con = matlab_round(totalTrials / 3)              # round(40/3) = 13
    num_neu = totalTrials - num_adv - num_con            # 13

    primeConditions = [1] * num_adv + [2] * num_con + [3] * num_neu
    random.shuffle(primeConditions)

    # 计数器：记录各组图片目前用到了第几张 (0-based)
    img_counters = [0, 0, 0]

    # 概率序列: 不允许同一概率连续出现 3 次 (与 MATLAB 相同的拒绝采样)
    isValidSeq = False
    while not isValidSeq:
        trialList = list(range(numProbs)) * trialsPerProb   # 0-based p_idx
        random.shuffle(trialList)
        isValidSeq = True
        for i in range(totalTrials - 2):
            if trialList[i] == trialList[i + 1] == trialList[i + 2]:
                isValidSeq = False
                break

    # --- 记录初始 Alpha ---
    initial_alpha_est = [0.6 + 0.2 * random.random() for _ in range(numProbs)]
    alpha_est = list(initial_alpha_est)

    step_ladder = [0.1, 0.05, 0.02, 0.005]
    reversal_count = [0] * numProbs
    prev_choice = [-1] * numProbs

    # 数据记录
    data_rows = []

    # =====================================================================
    # 3. 实验主循环
    # =====================================================================
    welcome_text = ('欢迎被试: %s (编号: %s)\n\n按任意键开始实验...'
                    % (subNamePinyin, subID))
    make_text(welcome_text).draw()
    win.flip()
    event.clearEvents()
    event.waitKeys()   # 对应 KbStrokeWait

    expClock = core.Clock()   # 实验全局时钟 (用于记录 onset 时间)

    for t in range(totalTrials):

        p_idx = trialList[t]                 # 0-based
        p_val = probabilities[p_idx]
        current_alpha = alpha_est[p_idx]

        # =================================================================
        # 在决策前呈现图片刺激 (Prime)
        # =================================================================
        current_prime = primeConditions[t]   # 1=adv, 2=con, 3=neu

        if current_prime == 1:
            idx = img_counters[0] % len(files_adv)
            img_path = files_adv[idx]
            img_counters[0] += 1
        elif current_prime == 2:
            idx = img_counters[1] % len(files_con)
            img_path = files_con[idx]
            img_counters[1] += 1
        else:
            idx = img_counters[2] % len(files_neu)
            img_path = files_neu[idx]
            img_counters[2] += 1

        img_name = os.path.basename(img_path)

        # 读取图片, 屏幕中央按原始尺寸呈现 (对应 MakeTexture + DrawTexture)
        img_stim = visual.ImageStim(win, image=img_path, units='pix', pos=(0, 0))

        # ----------------- Prime 视觉 Trigger (同帧 Flip) -----------------
        img_stim.draw()
        trigger_square.draw()
        win.flip()
        prime_onset_time = expClock.getTime()
        core.wait(TRIGGER_DUR)               # 方块只出现 50ms
        img_stim.draw()                      # 刷新屏幕, 只保留图片
        win.flip()
        core.wait(PRIME_DUR - TRIGGER_DUR)   # 图片总呈现时间 2.0 秒
        # ------------------------------------------------------------------

        prime_code = 10 + current_prime      # 11/12/13

        # 呈现注视点作为缓冲 (ISI: 0.5 秒)
        fixation.draw()
        win.flip()
        core.wait(ISI_DUR)

        # =================================================================
        # 原有的风险决策计算与呈现 (与 MATLAB 完全一致)
        # =================================================================
        ST_amount = random.randint(10, 20)   # 对应 randi([10,20])
        RG_amount = ST_amount * (1.0 / p_val) ** (1.0 / current_alpha)

        if RG_amount <= ST_amount + 0.1:
            RG_amount = ST_amount + 0.1
        elif RG_amount > 100:
            RG_amount = 100
        RG_amount = matlab_round(RG_amount)

        st_side = random.randint(1, 2)       # 对应 randi(2)

        str_ST = '100%% 获得\n%d 元' % ST_amount
        str_RG = '%d%% 获得\n%d 元' % (int(matlab_round(p_val * 100)), RG_amount)

        if st_side == 1:
            str_Left = str_ST
            str_Right = str_RG
        else:
            str_Left = str_RG
            str_Right = str_ST

        # MATLAB: left_rect = [0, 0, 0.70*W, H] -> 中心 x = 0.35W (即中心原点 -0.15W)
        #         right_rect = [0.30*W, 0, W, H] -> 中心 x = 0.65W (即中心原点 +0.15W)
        left_text = make_text(str_Left, pos=(-0.15 * win_w, 0))
        right_text = make_text(str_Right, pos=(0.15 * win_w, 0))

        left_text.draw()
        right_text.draw()
        fixation.draw()
        event.clearEvents()
        win.flip()
        decision_onset = expClock.getTime()  # 对应 vbl

        respToBeMade = True
        choice = 2      # 默认 2 (Timeout)
        rt = 0.0
        reward = 0
        is_reversal = 0

        while respToBeMade:
            keys = event.getKeys(keyList=['left', 'right', 'escape'],
                                 timeStamped=expClock)
            if keys:
                key_name, key_time = keys[0]
                if key_name == 'left':
                    rt = key_time - decision_onset
                    choice = 0 if st_side == 1 else 1
                    respToBeMade = False
                elif key_name == 'right':
                    rt = key_time - decision_onset
                    choice = 0 if st_side == 2 else 1
                    respToBeMade = False
                elif key_name == 'escape':
                    raise SystemExit('实验被主试中止。')

            if respToBeMade and (expClock.getTime() - decision_onset) >= DECISION_MAX:
                respToBeMade = False
                choice = 2
                rt = DECISION_MAX

        feedback_code = ''
        feedback_onset_time = ''

        if choice == 2:
            # ------------------------- Timeout 提示 -------------------------
            warning_text = '作答超时！\n\n请集中注意力，在 5 秒内做出选择。'
            make_text(warning_text, color=RED).draw()
            win.flip()
            core.wait(TIMEOUT_DUR)

        else:
            if choice == 0:
                reward = ST_amount
            elif choice == 1:
                if random.random() <= p_val:
                    reward = RG_amount
                else:
                    reward = 0

            # --------------- Feedback 前 Jitter (0.8 ~ 1.2 秒) ---------------
            win.flip()   # 清屏
            core.wait(random.uniform(JITTER_MIN, JITTER_MAX))

            # ----------------- Feedback 视觉 Trigger (同帧 Flip) -----------------
            feedback_str = '获得 %d 元' % reward
            feedback_text = make_text(feedback_str)
            feedback_text.draw()
            trigger_square.draw()
            win.flip()
            feedback_onset_time = expClock.getTime()
            core.wait(TRIGGER_DUR)                 # 方块只出现 50ms
            feedback_text.draw()                   # 刷新屏幕, 只保留 Feedback
            win.flip()
            core.wait(FEEDBACK_DUR - TRIGGER_DUR)  # Feedback 总呈现 1.0 秒
            # ---------------------------------------------------------------

            if choice == 0:
                feedback_code = 21                 # ST feedback
            elif reward > 0:
                feedback_code = 22                 # RG win
            else:
                feedback_code = 23                 # RG loss

            # -------------------- Adaptive Alpha 更新 --------------------
            if prev_choice[p_idx] != -1 and prev_choice[p_idx] != choice:
                is_reversal = 1
                reversal_count[p_idx] += 1

            step_idx = min(reversal_count[p_idx], len(step_ladder) - 1)
            current_step = step_ladder[step_idx]

            if choice == 0:
                alpha_est[p_idx] -= current_step
            elif choice == 1:
                alpha_est[p_idx] += current_step

            if alpha_est[p_idx] < 0.2:
                alpha_est[p_idx] = 0.2
            elif alpha_est[p_idx] > 2.0:
                alpha_est[p_idx] = 2.0

            prev_choice[p_idx] = choice

        # 记录数据
        if choice == 0:
            choice_label = 'ST'
        elif choice == 1:
            choice_label = 'RG'
        else:
            choice_label = 'Timeout'

        if current_prime == 1:
            prime_label = 'Adventure'
        elif current_prime == 2:
            prime_label = 'Conservative'
        else:
            prime_label = 'Neutral'

        data_rows.append({
            'SubID': subID,
            'Trial': t + 1,
            'Prime_Condition': prime_label,
            'Image_Name': img_name,
            'Probability': p_val,
            'Alpha_Est': current_alpha,
            'ST_Amount': ST_amount,
            'RG_Amount': RG_amount,
            'Choice_Num': choice,
            'Choice_Label': choice_label,
            'RT_sec': rt,
            'Is_Reversal': is_reversal,
            'Reward': reward,
            'Prime_Code': prime_code,
            'Feedback_Code': feedback_code,
            'Prime_Onset_Time': prime_onset_time,
            'Feedback_Onset_Time': feedback_onset_time,
        })

        # ITI (0.5 秒空屏)
        win.flip()
        core.wait(ITI_DUR)

    # =====================================================================
    # 实验结束
    # =====================================================================
    make_text('实验结束，感谢您的参与！\n\n数据正在保存，请按任意键退出...').draw()
    win.flip()
    event.clearEvents()
    event.waitKeys()

    win.close()
    win = None

    # =====================================================================
    # 数据处理与 CSV 文件保存
    # =====================================================================
    fieldnames = ['SubID', 'Trial', 'Prime_Condition', 'Image_Name',
                  'Probability', 'Alpha_Est',
                  'ST_Amount', 'RG_Amount', 'Choice_Num',
                  'Choice_Label', 'RT_sec', 'Is_Reversal', 'Reward',
                  'Prime_Code', 'Feedback_Code',
                  'Prime_Onset_Time', 'Feedback_Onset_Time']

    mainFileName = os.path.join(BASE_DIR,
                                'RiskDM_Data_%s_%s.csv' % (subID, subNamePinyin))
    with open(mainFileName, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data_rows)

    alphaFileName = os.path.join(BASE_DIR,
                                 'RiskDM_Alpha_%s_%s.csv' % (subID, subNamePinyin))
    with open(alphaFileName, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(['Probability', 'Initial_Alpha', 'Final_Alpha'])
        for i in range(numProbs):
            writer.writerow([probabilities[i], initial_alpha_est[i], alpha_est[i]])

    # --- 终端打印提示 ---
    print('')
    print('=== 被试: %s (编号: %s) 数据已成功保存 ===' % (subNamePinyin, subID))
    print('1. 试次行为数据: %s' % mainFileName)
    print('2. Alpha结果数据: %s' % alphaFileName)
    print('====================================================================')

except SystemExit as e:
    if win is not None:
        win.close()
    print(str(e))
except Exception:
    if win is not None:
        win.close()
    traceback.print_exc()   # 打印完整报错信息, 不被 core.quit() 吞掉
finally:
    core.quit()
