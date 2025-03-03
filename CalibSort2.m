function [orderedPts,indexs] = CalibSort2(unorder_pts,mode)
% 功能：相机标定点顺序提取，对无序点集按照“从上到下，从左到右”的原则排序。
% 思路：首先根据四边形点集先找到4个角点，主要是利用凸包多边形思想，包括四个角点方向顺序确定，随后通过预先规定的对应四点
% 坐标计算透视变换矩阵，其次通过透视变换把所有点映射到到正方形上面来，
% 最后对正方形上面的点集进行“从小到大”的原则排序，排序好的索引应用到原无序点集即可完成
%
% 输入：unorder_pts，n*2 double，[x,y]无序点集坐标
%      mode，1*2 double，模式，[rows,cols] 标定板点行列个数
% 输出：orderedPts，n*2 double，[x,y]有序点集坐标
%       indexs， n*1 double， 索引值(可选)
% 注意：unorder_pts 必须是满足投影变换的点集,点集个数与mode指定大小要一致
%
% EXAMPLE:
%        mode = [10,6];% rows*cols 个标定点模式
%        [X,Y] = meshgrid(1:mode(2),1:mode(1));
%        unorderedPts = [X(:),Y(:)];
%        [orderedPts,indexs] =  CalibSort2(unorderedPts,mode);
% 
%        % 绘制排序好后的点
%        figure;
%        hold on;
%        plot(orderedPts(:,1),orderedPts(:,2),'b.',MarkerSize=20)
%        text(orderedPts(:,1),orderedPts(:,2),string(1:prod(mode)))
%        grid
%        title('ordered points')
%
% author:cuixingxing
% email: cuixingxing150@gmail.com
% 2018.7.22 首次创建
% 2025.3.2 修改算法


arguments
    unorder_pts (:,2) double
    mode (:,:) double
end

%% Step1,找出无序平面点集的4个顶点
% 1. 找凸包顶点，逆时针顺序
indexConvHull = convhull(unorder_pts);

% 绘图显示凸包多边形
% figure;
% plot(unorder_pts(:,1),unorder_pts(:,2),'*')
% hold on
% plot(unorder_pts(indexConvHull,1),unorder_pts(indexConvHull,2))
% title('凸包多边形')

% 2.计算多边形每个顶点的夹角
convHullPts = unorder_pts(indexConvHull,:);
numVertices = size(convHullPts,1)-1;
angles = 180*ones(numVertices,1);
for idx = 1:numVertices
    if idx == 1
        prevPt = convHullPts(end-1,:);
    else
        prevPt = convHullPts(idx-1,:);
    end
    currPt = convHullPts(idx,:);
    nextPt = convHullPts(idx+1,:);

    % 计算相邻的2条边向量的夹角，[0,180]之间范围
    vecLine1 = prevPt-currPt; 
    vecLine2 = nextPt-currPt;
    angles(idx) = acosd(dot(vecLine1,vecLine2)./(vecnorm(vecLine1)*vecnorm(vecLine2)));
end

% 3. 找出最小顶点角度，top4，即4个顶点
[~,indexVertices] = mink(angles,4);
vertices = convHullPts(indexVertices,:);

% 4. 凸包顶点排序,思想：利用向量叉积确定凸包方向, https://github.com/cuixing158/rotatedRectangleIntersect/blob/7fa6cf7cb9d9ac9335d17b05f429a47f8604fafe/rotatedRectangleIntersection.m#L199
N = size(vertices,1);
for i = 1:N-2
    pt1 = vertices(i,:);% 表示第i个点已经完成排序，本次循环待查找第i+1个点的坐标
    vecall = vertices(i+1:end,:)-repmat(pt1,N-i,1);% 剩余未排序的N-i个点与pt1的方向向量
    vec1 = vecall(1,:);% 待寻找的基础向量，对应的点坐标索引为第i+1个
    for j = 2:size(vecall,1)
        vec2 = vecall(j,:);% 注意！对应的点坐标在vertices数组中索引为i+j
        if vec1(1)*vec2(2)-vec2(1)*vec1(2)<0
            vec1 = vec2;
            temp = vertices(i+1,:);
            vertices(i+1,:) =  vertices(i+j,:);
            vertices(i+j,:) = temp;
            vecall = vertices(i+1:end,:)-repmat(pt1,N-i,1);
        end
    end
end
conners = vertices;

% 5. 找到“左下角点”顺序
threshold = inf;
for i = 1:N
    currPt = conners(i,:);
    if i == N
        nextPt = conners(1,:);
    else
        nextPt = conners(i+1,:);
    end
    
    vecLine1 = nextPt-currPt;
    vecLine2 = [1,0];
    angle = acosd(dot(vecLine1,vecLine2)./(vecnorm(vecLine1)*vecnorm(vecLine2)));

    if vecLine1(1)>0 && angle<threshold
        newconners = circshift(conners,1-i,1);
        threshold = angle;
    end
end

% 绘图显示角点顺序
% figure;
% grid;
% hold on;
% for i = 1:4
%     plot(newconners(i,1),newconners(i,2),'bo');
%     text(newconners(i,1),newconners(i,2),num2str(i));
% end
% title('找到的原四个角点')

%% Step 2, 计算透视变换矩阵
% 把点变换到正方形形状上来,便于排序
squre_pts = [0,0;
    1,0;
    1,1;
    0,1];% 注意顺序，是图像坐标系下
tform = fitgeotrans(newconners,squre_pts,'Projective');
[~,Y] = transformPointsForward(tform,unorder_pts(:,1),unorder_pts(:,2));

%% Step 3, 排序
[~,y_increasing_index] = sort(Y);

numPts = size(unorder_pts,1);% 初始化
orderedPts = zeros(numPts,2); % 初始化
indexs = ones(numPts,1);
for irow = 1:mode(1)
    idxStart = (irow-1)*mode(2)+1;
    idxEnd =  idxStart+mode(2)-1;

    currRowIndexs = y_increasing_index(idxStart:idxEnd);
    currRowPts = unorder_pts(currRowIndexs,:);
    [rowPts,indexRow] = sortrows(currRowPts,1,"ascend");

    orderedPts(idxStart:idxEnd,:) = rowPts;
    indexs(idxStart:idxEnd) = currRowIndexs(indexRow);
end


