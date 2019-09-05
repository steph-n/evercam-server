import cv2
import moviepy.editor as mpe
import numpy as np
import os
import glob

def remove_date(video_id):
    video_id = str(video_id, 'utf-8')
    path = "./lib/python/"
    if os.path.exists(path + video_id + ".mp4"):
        cap = cv2.VideoCapture(path + video_id + ".mp4")
        frame_width = int(cap.get(3))
        frame_height = int(cap.get(4))
        mask = np.zeros((frame_height,frame_width,1), np.uint8)
        ret, img = cap.read()
        img = cv2.resize(img, (0,0), fx=0.5, fy=0.5)
        img_gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        y1 = x1 = 2000
        h1 = w1 = 0
        fgbg = cv2.createBackgroundSubtractorMOG2()
        for filename in sorted(os.listdir('./lib/python/time')):
            template = cv2.imread('./lib/python/time/' + filename,0)
            w, h = template.shape[::-1]
            res = cv2.matchTemplate(img_gray,template,cv2.TM_CCOEFF_NORMED)
            threshold = 0.8
            loc = np.where( res >= threshold)
            for pt in zip(*loc[::-1]):
                if pt[0] < x1:
                    x1 = pt[0]
                if pt[1] < y1:
                    y1 = pt[1]
                if h > h1:
                    h1 = h
                if pt[0]> w1:
                    w1 = pt[0] + w

        cap.release()
        cap = cv2.VideoCapture(path + video_id + ".mp4")
        out = cv2.VideoWriter(path + "wd-" + video_id + ".mp4", cv2.VideoWriter_fourcc(*'H264'), 24, (frame_width,frame_height))
        print("Removing timestamp!")
        while cap.isOpened():
            ret, img = cap.read()
            if img is None:
                break
            img = cv2.resize(img, (0,0), fx=0.5, fy=0.5)
            date = img[y1:y1+h1, x1:x1+w1]
            date2 = np.zeros((h1,w1,3), np.uint8)
            for y in range(0, w1):
                for x in range(0, h1):
                    RGB = (date[x,y,2], date[x,y,1], date[x,y,0])
                    if RGB[0] < 50 and RGB[1] < 50 and RGB[2] < 50:
                        date2[x,y] = (255,255,255)
                    elif RGB[0] > 210 and RGB[1] > 210 and RGB[2] > 210:
                        date2[x,y] = (255,255,255)
                    else:
                        date2[x,y] = (0,0,0)
            blank_image = np.zeros((img.shape[0],img.shape[1]), np.uint8)
            x_offset=x1
            y_offset=y1
            gray_image = cv2.cvtColor(date2, cv2.COLOR_BGR2GRAY)
            blank_image[y_offset:y_offset + date.shape[0], x_offset:x_offset + date.shape[1]] = gray_image
            dst = cv2.inpaint(img,blank_image,3,cv2.INPAINT_TELEA)
            dst = cv2.resize(dst, (0,0), fx=2, fy=2)
            fgbg.apply(dst,None,0.5)
            bgmodel=fgbg.getBackgroundImage()
            if ret == True:
                out.write(bgmodel)
            else:
                break
            key = cv2.waitKey(1)
            if key == 27:
                break
        print("timestamp removed.")
        out.release()
        cap.release()
        cv2.destroyAllWindows()

def remove_date_2(video_id, images_directory):
    video_id = str(video_id, 'utf-8')
    images_directory = str(images_directory, 'utf-8')
    if os.path.exists(images_directory):
        url = os.listdir(images_directory)[0]
        img = cv2.imread(images_directory + "/" +  url)
        frame_height, frame_width, channels = img.shape
        img = cv2.resize(img, (0,0), fx=0.5, fy=0.5)
        mask = np.zeros((frame_height,frame_width,1), np.uint8)

        img_gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        y1 = x1 = 2000
        h1 = w1 = 0
        for filename in sorted(os.listdir('lib/python/time')):
            template = cv2.imread('lib/python/time/' + filename,0)
            w, h = template.shape[::-1]
            res = cv2.matchTemplate(img_gray,template,cv2.TM_CCOEFF_NORMED)
            threshold = 0.8
            loc = np.where( res >= threshold)
            for pt in zip(*loc[::-1]):
                if pt[0] < x1:
                    x1 = pt[0]
                if pt[1] < y1:
                    y1 = pt[1]
                if h > h1:
                    h1 = h
                if pt[0]> w1:
                    w1 = pt[0] + w

        out = cv2.VideoWriter(images_directory + "/output.mp4", cv2.VideoWriter_fourcc(*'H264'), 24, (frame_width,frame_height))
        fgbg = cv2.createBackgroundSubtractorMOG2()
        for filename in sorted(glob.glob(images_directory+"/*.jpg")):
            image = cv2.imread(filename)
            img = cv2.resize(image, (0,0), fx=0.5, fy=0.5)
            date = img[y1:y1+h1, x1:x1+w1]
            we, he, channelsDate = date.shape
            for y in range(0, he):
                for x in range(0, we):
                    RGB = (date[x,y,2], date[x,y,1], date[x,y,0])
                    if RGB[0] < 50 and RGB[1] < 50 and RGB[2] < 50:
                        if RGB[0] < 210 and RGB[1] < 210 and RGB[2] < 210:
                            date[x,y] = (255,255,255)
                    elif RGB[0] > 210 and RGB[1] > 210 and RGB[2] > 210:
                        date[x,y] = (255,255,255)
                    else:
                        date[x,y] = (0,0,0)
            img = cv2.imread(filename, 1)
            img = cv2.resize(img, (0,0), fx=0.5, fy=0.5)
            blank_image = np.zeros((img.shape[0],img.shape[1]), np.uint8)
            x_offset=x1
            y_offset=y1
            gray_image = cv2.cvtColor(date, cv2.COLOR_BGR2GRAY)
            blank_image[y_offset:y_offset + date.shape[0], x_offset:x_offset + date.shape[1]] = gray_image
            dst = cv2.inpaint(img,blank_image,3,cv2.INPAINT_TELEA)
            fgbg.apply(dst,None,0.5)
            bgmodel=fgbg.getBackgroundImage()
            bgmodel = cv2.resize(bgmodel, (frame_width,frame_height))
            out.write(bgmodel)
        out.release()
        cv2.destroyAllWindows()
