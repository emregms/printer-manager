import React, { useEffect, useState } from 'react';

interface PrintPageProps {
  pageNumber: number;
  isActive: boolean;
  status: 'pending' | 'printing' | 'cleaning' | 'completed';
  timeRemaining?: number;
  totalTime?: number;
}

export const PrintPage: React.FC<PrintPageProps> = ({
  pageNumber,
  isActive,
  status,
  timeRemaining = 0,
  totalTime = 0,
}) => {
  const [progress, setProgress] = useState<number>(0);

  useEffect(() => {
    if (!isActive || !totalTime) {
      setProgress(0);
      return;
    }
    setProgress(Math.max(0, Math.min(100, ((totalTime - timeRemaining) / totalTime) * 100)));
  }, [isActive, timeRemaining, totalTime]);

  // Status renkleri ve metinleri
  const statusConfig = {
    pending: { color: '#e0e0e0', text: 'Bekliyor', icon: '⌛' },
    printing: { color: '#4CAF50', text: 'Yazdırılıyor', icon: '🖨️' },
    cleaning: { color: '#FFA726', text: 'Temizleniyor', icon: '🧹' },
    completed: { color: '#2196F3', text: 'Tamamlandı', icon: '✓' },
  };

  const currentStatus = statusConfig[status];

  return (
    <div
      style={{
        position: 'relative',
        border: isActive ? `3px solid ${currentStatus.color}` : '1px solid #ddd',
        borderRadius: '8px',
        backgroundColor: isActive ? '#f9f9f9' : '#ffffff',
        padding: '12px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        boxShadow: isActive ? `0 0 8px rgba(0, 0, 0, 0.2)` : 'none',
        transition: 'all 0.3s ease',
        width: '120px',
        height: '150px',
      }}
    >
      <div style={{ 
        fontSize: '14px', 
        fontWeight: 'bold', 
        marginBottom: '4px', 
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: '100%'
      }}>
        {isActive && <span style={{ marginRight: '5px' }}>{currentStatus.icon}</span>}
        Sayfa {pageNumber}
      </div>
      
      <div style={{
        width: '100px',
        height: '120px',
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        backgroundColor: '#fff',
        border: '1px solid #eee',
        position: 'relative',
      }}>
        <span style={{ 
          fontSize: '24px', 
          fontWeight: 'bold',
          color: '#888'
        }}>
          {pageNumber}
        </span>
        
        {isActive && status !== 'pending' && status !== 'completed' && (
          <div style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            height: '4px',
            width: `${progress}%`,
            backgroundColor: currentStatus.color,
            transition: 'width 0.1s ease-in-out'
          }} />
        )}
      </div>
      
      {isActive && (
        <div style={{ 
          position: 'absolute', 
          bottom: '4px', 
          right: '4px', 
          background: currentStatus.color, 
          color: 'white', 
          padding: '2px 6px', 
          borderRadius: '10px', 
          fontSize: '10px',
          display: 'flex',
          alignItems: 'center',
        }}>
          {currentStatus.text}
          {(status === 'printing' || status === 'cleaning') && timeRemaining > 0 && (
            <span style={{ marginLeft: '4px' }}>
              {Math.ceil(timeRemaining / 1000)} sn
            </span>
          )}
        </div>
      )}
    </div>
  );
};

